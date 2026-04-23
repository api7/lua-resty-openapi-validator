-- Request body validation.
-- Handles JSON, form-urlencoded, and multipart/form-data body parsing
-- and validation.

local _M = {}

local type       = type
local pairs      = pairs
local pcall      = pcall
local tonumber   = tonumber
local str_find   = string.find
local str_lower  = string.lower
local sub_str    = string.sub
local str_gsub   = string.gsub
local str_char   = string.char
local str_match  = string.match
local str_gmatch = string.gmatch
local tab_insert = table.insert

local cjson      = require("cjson.safe")

local jsonschema
local has_jsonschema = pcall(function()
    jsonschema = require("jsonschema")
end)

local errors     = require("resty.openapi_validator.errors")

-- Schema validator cache
local validator_cache = setmetatable({}, { __mode = "k" })

local function get_validator(schema)
    if not has_jsonschema then
        return nil
    end
    if validator_cache[schema] then
        return validator_cache[schema]
    end
    local ok, v = pcall(jsonschema.generate_validator, schema)
    if ok and v then
        validator_cache[schema] = v
        return v
    end
    return nil
end


local function is_json_content_type(ct)
    if not ct then return false end
    ct = str_lower(ct)
    return str_find(ct, "application/json", 1, true) ~= nil
        or str_find(ct, "+json", 1, true) ~= nil
end


local function is_form_content_type(ct)
    if not ct then return false end
    ct = str_lower(ct)
    return str_find(ct, "application/x-www-form-urlencoded", 1, true) ~= nil
end


local function is_multipart_content_type(ct)
    if not ct then return false end
    ct = str_lower(ct)
    return str_find(ct, "multipart/form-data", 1, true) ~= nil
end


local function url_decode(s)
    s = str_gsub(s, "+", " ")
    s = str_gsub(s, "%%(%x%x)", function(hex)
        return str_char(tonumber(hex, 16))
    end)
    return s
end


-- Parse application/x-www-form-urlencoded body into a table.
local function parse_form_urlencoded(body_str)
    local result = {}
    if not body_str or body_str == "" then
        return result
    end
    for pair in str_gmatch(body_str, "[^&]+") do
        local eq = str_find(pair, "=", 1, true)
        if eq then
            local key = url_decode(sub_str(pair, 1, eq - 1))
            local val = url_decode(sub_str(pair, eq + 1))
            result[key] = val
        else
            result[url_decode(pair)] = ""
        end
    end
    return result
end


-- Coerce form values to match schema types.
local function coerce_form_value(value, prop_schema)
    if not prop_schema or type(value) ~= "string" then
        return value
    end
    local stype = prop_schema.type
    if stype == "integer" or stype == "number" then
        return tonumber(value) or value
    elseif stype == "boolean" then
        if value == "true" then return true end
        if value == "false" then return false end
        return value
    elseif stype == "object" or stype == "array" then
        local decoded = cjson.decode(value)
        if decoded ~= nil then return decoded end
    end
    return value
end


-- Coerce form data values according to schema properties.
local function coerce_form_data(data, schema)
    if not schema or not schema.properties then
        return data
    end
    for key, val in pairs(data) do
        if schema.properties[key] then
            data[key] = coerce_form_value(val, schema.properties[key])
        end
    end
    return data
end


-- Extract multipart boundary from content-type header.
local function extract_boundary(ct)
    if not ct then return nil end
    local boundary = str_match(ct, "boundary=([^;%s]+)")
    if boundary then
        boundary = str_gsub(str_gsub(boundary, '^"', ''), '"$', '')
    end
    return boundary
end


-- Parse multipart/form-data body.
-- Returns a table of { field_name = value }.
local function parse_multipart(body_str, boundary)
    if not body_str or not boundary then
        return {}
    end

    local result = {}
    local delimiter = "--" .. boundary
    local end_delimiter = delimiter .. "--"

    local pos = 1
    while true do
        local start = str_find(body_str, delimiter, pos, true)
        if not start then break end

        local next_start = str_find(body_str, delimiter,
                                    start + #delimiter, true)
        if not next_start then break end

        local part = sub_str(body_str, start + #delimiter, next_start - 1)
        if sub_str(part, 1, 2) == "\r\n" then
            part = sub_str(part, 3)
        end
        if sub_str(part, -2) == "\r\n" then
            part = sub_str(part, 1, -3)
        end

        local header_end = str_find(part, "\r\n\r\n", 1, true)
        if header_end then
            local headers_str = sub_str(part, 1, header_end - 1)
            local body = sub_str(part, header_end + 4)

            local name = str_match(headers_str, 'name="([^"]+)"')
            if name then
                local part_ct = str_match(headers_str,
                                          "[Cc]ontent%-[Tt]ype:%s*([^\r\n]+)")
                if part_ct and is_json_content_type(part_ct) then
                    local decoded = cjson.decode(body)
                    result[name] = decoded ~= nil and decoded or body
                else
                    result[name] = body
                end
            end
        end

        pos = next_start
        if sub_str(body_str, next_start,
                   next_start + #end_delimiter - 1) == end_delimiter then
            break
        end
    end

    return result
end


-- Find the matching body schema for a given content type.
local function find_body_schema_for_content_type(route, content_type)
    if not route.body_content then
        return route.body_schema
    end

    if content_type then
        local ct_lower = str_lower(content_type)
        for media_type, media_obj in pairs(route.body_content) do
            local mt_lower = str_lower(media_type)
            if str_find(ct_lower, mt_lower, 1, true) then
                return media_obj.schema
            end
        end
    end

    if route.body_content["*/*"] then
        return route.body_content["*/*"].schema
    end

    return route.body_schema
end


-- Check if a schema (or its allOf sub-schemas) declares the discriminator
-- property with an enum that contains the given value.
local function branch_matches_discriminator_enum(branch, prop_name, value)
    local function check_props(s)
        local p = s.properties and s.properties[prop_name]
        if p and p.enum then
            for _, v in ipairs(p.enum) do
                if v == value then
                    return true
                end
            end
        end
        return false
    end

    if check_props(branch) then
        return true
    end

    if branch.allOf then
        for _, sub in ipairs(branch.allOf) do
            if check_props(sub) then
                return true
            end
        end
    end

    return false
end


-- Find the branch whose _ref matches the mapping target.
local function find_branch_by_mapping(branches, mapping, value)
    local target_ref = mapping[value]
    if not target_ref then
        return nil
    end

    for _, branch in ipairs(branches) do
        if branch._ref == target_ref then
            return branch
        end
        if branch.allOf then
            for _, sub in ipairs(branch.allOf) do
                if sub._ref == target_ref then
                    return branch
                end
            end
        end
    end

    return nil
end


-- Resolve an OpenAPI discriminator to select the correct oneOf/anyOf branch.
-- Returns (selected_schema, nil) on success, or (nil, error_string) on failure.
-- Returns (nil, nil) when the schema has no discriminator.
local function resolve_discriminator(schema, body_data)
    local disc = schema.discriminator
    if not disc or not disc.propertyName then
        return nil, nil
    end

    local prop_name = disc.propertyName
    local branches = schema.oneOf or schema.anyOf
    if not branches then
        return nil, nil
    end

    if type(body_data) ~= "table" then
        return nil, "discriminator property '" .. prop_name .. "' is missing"
    end

    local value = body_data[prop_name]
    if value == nil then
        return nil, "discriminator property '" .. prop_name .. "' is missing"
    end

    -- try mapping-based lookup first (uses _ref annotations from ref resolver)
    if disc.mapping then
        local branch = find_branch_by_mapping(branches, disc.mapping, value)
        if branch then
            return branch, nil
        end
    end

    -- fallback: match by enum on the discriminator property
    for _, branch in ipairs(branches) do
        if branch_matches_discriminator_enum(branch, prop_name, value) then
            return branch, nil
        end
    end

    return nil, "discriminator value '" .. tostring(value)
               .. "' does not match any schema"
end


-- Check for readOnly properties present in the request body data.
local function check_readonly_properties(data, schema, errs)
    if type(data) ~= "table" or type(schema) ~= "table" then
        return
    end
    local props = schema.properties
    if not props then
        return
    end
    for key, prop_schema in pairs(props) do
        if prop_schema.readOnly and data[key] ~= nil then
            tab_insert(errs, errors.new("body", key,
                "readOnly property '" .. key .. "' should not be sent in request"))
        end
    end
end


-- Validate request body.
function _M.validate(route, body_str, content_type, opts)
    opts = opts or {}
    local errs = {}

    -- Normalize non-string content_type (e.g. cjson.null sentinel — which is
    -- userdata and truthy in Lua, so naive `and content_type` checks would
    -- let it through and crash inside str_lower) to nil so downstream code
    -- can treat it uniformly with "header absent".
    if type(content_type) ~= "string" then
        content_type = nil
    end

    if route.body_required then
        if body_str == nil or body_str == "" then
            tab_insert(errs, errors.new("body", nil, "request body is required"))
            return false, errs
        end
    end

    if not route.body_schema and not route.body_content then
        return true, nil
    end

    if body_str == nil or body_str == "" then
        return true, nil
    end

    -- check content-type is declared in the spec
    if route.body_content and content_type then
        local ct_lower = str_lower(content_type)
        local found = false
        for media_type in pairs(route.body_content) do
            local mt_lower = str_lower(media_type)
            if str_find(ct_lower, mt_lower, 1, true)
               or media_type == "*/*" then
                found = true
                break
            end
        end
        if not found then
            tab_insert(errs, errors.new("body", nil,
                "content type " .. content_type
                .. " is not declared in the spec"))
            return false, errs
        end
    end

    local schema = find_body_schema_for_content_type(route, content_type)
    if not schema then
        return true, nil
    end

    if is_json_content_type(content_type) then
        local body_data, decode_err = cjson.decode(body_str)
        if body_data == nil and decode_err then
            tab_insert(errs, errors.new("body", nil,
                "invalid JSON body: " .. (decode_err or "decode error")))
            return false, errs
        end

        if not opts.exclude_readonly then
            check_readonly_properties(body_data, schema, errs)
        end

        local effective_schema = schema
        local disc_schema, disc_err = resolve_discriminator(schema, body_data)
        if disc_err then
            tab_insert(errs, errors.new("body", nil, disc_err))
        elseif disc_schema then
            effective_schema = disc_schema
        end

        local validator = get_validator(effective_schema)
        if validator then
            local ok, err = validator(body_data)
            if not ok then
                local msg = type(err) == "string" and err
                            or "body validation failed"
                tab_insert(errs, errors.new("body", nil, msg))
            end
        end

    elseif is_form_content_type(content_type) then
        local form_data = parse_form_urlencoded(body_str)
        form_data = coerce_form_data(form_data, schema)

        if not opts.exclude_readonly then
            check_readonly_properties(form_data, schema, errs)
        end

        local validator = get_validator(schema)
        if validator then
            local ok, err = validator(form_data)
            if not ok then
                local msg = type(err) == "string" and err
                            or "body validation failed"
                tab_insert(errs, errors.new("body", nil, msg))
            end
        end

    elseif is_multipart_content_type(content_type) then
        local boundary = extract_boundary(content_type)
        if not boundary then
            tab_insert(errs, errors.new("body", nil,
                "missing multipart boundary"))
            return false, errs
        end

        local parts = parse_multipart(body_str, boundary)
        parts = coerce_form_data(parts, schema)

        local validator = get_validator(schema)
        if validator then
            local ok, err = validator(parts)
            if not ok then
                local msg = type(err) == "string" and err
                            or "body validation failed"
                tab_insert(errs, errors.new("body", nil, msg))
            end
        end

    else
        return true, nil
    end

    if #errs > 0 then
        return false, errs
    end
    return true, nil
end

return _M
