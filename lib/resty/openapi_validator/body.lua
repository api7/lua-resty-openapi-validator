--- Request body validation.
-- Handles JSON, form-urlencoded, and multipart/form-data body parsing and validation.

local _M = {}

local type = type
local pairs = pairs
local ipairs = ipairs
local find = string.find
local lower = string.lower
local sub = string.sub
local insert = table.insert
local tonumber = tonumber

local cjson = require("cjson.safe")

local jsonschema
local has_jsonschema, _ = pcall(function()
    jsonschema = require("jsonschema")
end)

local errors = require("resty.openapi_validator.errors")

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

--- Check if content type is JSON-like.
local function is_json_content_type(ct)
    if not ct then return false end
    ct = lower(ct)
    return find(ct, "application/json", 1, true) ~= nil
        or find(ct, "+json", 1, true) ~= nil
end

--- Check if content type is form-urlencoded.
local function is_form_content_type(ct)
    if not ct then return false end
    ct = lower(ct)
    return find(ct, "application/x-www-form-urlencoded", 1, true) ~= nil
end

--- Check if content type is multipart/form-data.
local function is_multipart_content_type(ct)
    if not ct then return false end
    ct = lower(ct)
    return find(ct, "multipart/form-data", 1, true) ~= nil
end

--- URL-decode a string.
local function url_decode(s)
    s = s:gsub("+", " ")
    s = s:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
    return s
end

--- Parse application/x-www-form-urlencoded body into a table.
local function parse_form_urlencoded(body_str)
    local result = {}
    if not body_str or body_str == "" then
        return result
    end
    for pair in body_str:gmatch("[^&]+") do
        local eq = find(pair, "=", 1, true)
        if eq then
            local key = url_decode(sub(pair, 1, eq - 1))
            local val = url_decode(sub(pair, eq + 1))
            result[key] = val
        else
            result[url_decode(pair)] = ""
        end
    end
    return result
end

--- Coerce form values to match schema types.
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

--- Coerce form data values according to schema properties.
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

--- Extract multipart boundary from content-type header.
local function extract_boundary(ct)
    if not ct then return nil end
    local boundary = ct:match("boundary=([^;%s]+)")
    if boundary then
        -- strip surrounding quotes
        boundary = boundary:gsub('^"', ''):gsub('"$', '')
    end
    return boundary
end

--- Parse multipart/form-data body.
-- Returns a table of { field_name = value }.
-- For JSON content-disposition parts, value is decoded JSON.
-- For file parts, returns the raw content.
local function parse_multipart(body_str, boundary)
    if not body_str or not boundary then
        return {}
    end

    local result = {}
    local delimiter = "--" .. boundary
    local end_delimiter = delimiter .. "--"

    -- split by boundary
    local pos = 1
    while true do
        local start = find(body_str, delimiter, pos, true)
        if not start then break end

        local next_start = find(body_str, delimiter, start + #delimiter, true)
        if not next_start then break end

        local part = sub(body_str, start + #delimiter, next_start - 1)
        -- strip leading \r\n
        if sub(part, 1, 2) == "\r\n" then
            part = sub(part, 3)
        end
        -- strip trailing \r\n
        if sub(part, -2) == "\r\n" then
            part = sub(part, 1, -3)
        end

        -- split headers and body
        local header_end = find(part, "\r\n\r\n", 1, true)
        if header_end then
            local headers_str = sub(part, 1, header_end - 1)
            local body = sub(part, header_end + 4)

            -- parse Content-Disposition for field name
            local name = headers_str:match('name="([^"]+)"')
            if name then
                -- check Content-Type of the part
                local part_ct = headers_str:match("[Cc]ontent%-[Tt]ype:%s*([^\r\n]+)")
                if part_ct and is_json_content_type(part_ct) then
                    local decoded = cjson.decode(body)
                    result[name] = decoded ~= nil and decoded or body
                else
                    result[name] = body
                end
            end
        end

        pos = next_start
        -- check if we hit the end delimiter
        if sub(body_str, next_start, next_start + #end_delimiter - 1) == end_delimiter then
            break
        end
    end

    return result
end

--- Find the matching body schema for a given content type from the route's content map.
local function find_body_schema_for_content_type(route, content_type)
    if not route.body_content then
        return route.body_schema
    end

    -- exact match
    if content_type then
        local ct_lower = lower(content_type)
        for media_type, media_obj in pairs(route.body_content) do
            local mt_lower = lower(media_type)
            if find(ct_lower, mt_lower, 1, true) then
                return media_obj.schema
            end
        end
    end

    -- fallback to */*
    if route.body_content["*/*"] then
        return route.body_content["*/*"].schema
    end

    return route.body_schema
end

--- Check for readOnly properties present in the request body data.
-- readOnly properties should not be sent in a request.
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
            insert(errs, errors.new("body", key,
                "readOnly property '" .. key .. "' should not be sent in request"))
        end
    end
end

--- Validate request body.
-- @param route table        matched route from router
-- @param body_str string    raw request body (may be nil or empty)
-- @param content_type string  Content-Type header value
-- @param opts table|nil     validation options:
--   - exclude_readonly (bool): if true, skip readOnly validation
--   - exclude_writeonly (bool): if true, skip writeOnly validation
-- @return boolean
-- @return table|nil  list of error tables
function _M.validate(route, body_str, content_type, opts)
    opts = opts or {}
    local errs = {}

    -- check if body is required
    if route.body_required then
        if body_str == nil or body_str == "" then
            insert(errs, errors.new("body", nil, "request body is required"))
            return false, errs
        end
    end

    -- no body schema means nothing to validate
    if not route.body_schema and not route.body_content then
        return true, nil
    end

    -- no body provided and not required → OK
    if body_str == nil or body_str == "" then
        return true, nil
    end

    -- check content-type is declared in the spec
    if route.body_content and content_type then
        local ct_lower = lower(content_type)
        local found = false
        for media_type in pairs(route.body_content) do
            local mt_lower = lower(media_type)
            if find(ct_lower, mt_lower, 1, true) or media_type == "*/*" then
                found = true
                break
            end
        end
        if not found then
            insert(errs, errors.new("body", nil,
                "content type " .. content_type .. " is not declared in the spec"))
            return false, errs
        end
    end

    -- get the right schema for this content type
    local schema = find_body_schema_for_content_type(route, content_type)
    if not schema then
        return true, nil
    end

    -- determine content type and validate accordingly
    if is_json_content_type(content_type) then
        -- parse JSON body
        local body_data, decode_err = cjson.decode(body_str)
        if body_data == nil and decode_err then
            insert(errs, errors.new("body", nil,
                "invalid JSON body: " .. (decode_err or "decode error")))
            return false, errs
        end

        -- check readOnly properties in request
        if not opts.exclude_readonly then
            check_readonly_properties(body_data, schema, errs)
        end

        -- validate against schema
        local validator = get_validator(schema)
        if validator then
            local ok, err = validator(body_data)
            if not ok then
                local msg = type(err) == "string" and err or "body validation failed"
                insert(errs, errors.new("body", nil, msg))
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
                local msg = type(err) == "string" and err or "body validation failed"
                insert(errs, errors.new("body", nil, msg))
            end
        end

    elseif is_multipart_content_type(content_type) then
        local boundary = extract_boundary(content_type)
        if not boundary then
            insert(errs, errors.new("body", nil, "missing multipart boundary"))
            return false, errs
        end

        local parts = parse_multipart(body_str, boundary)
        parts = coerce_form_data(parts, schema)

        local validator = get_validator(schema)
        if validator then
            local ok, err = validator(parts)
            if not ok then
                local msg = type(err) == "string" and err or "body validation failed"
                insert(errs, errors.new("body", nil, msg))
            end
        end

    else
        -- unsupported content type, skip validation
        return true, nil
    end

    if #errs > 0 then
        return false, errs
    end
    return true, nil
end

return _M
