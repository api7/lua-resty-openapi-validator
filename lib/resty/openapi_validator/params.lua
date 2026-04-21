--- Parameter coercion and validation.
-- Handles path, query, and header parameters:
-- 1. Type coercion from string to schema-declared type
-- 2. Style/explode deserialization (form, simple, label, matrix, deepObject)
-- 3. JSON Schema validation via api7/jsonschema

local _M = {}

local type = type
local tonumber = tonumber
local pairs = pairs
local ipairs = ipairs
local lower = string.lower
local find = string.find
local sub = string.sub
local gsub = string.gsub
local insert = table.insert
local concat = table.concat

local cjson
local has_cjson, _ = pcall(function()
    cjson = require("cjson.safe")
end)

local jsonschema
local has_jsonschema, _ = pcall(function()
    jsonschema = require("jsonschema")
end)

local errors = require("resty.openapi_validator.errors")

-- Schema validator cache: schema_table → validator_function
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

--- Coerce a string value to the type declared in schema.
-- @param value string   raw value from request
-- @param schema table   parameter schema
-- @return any   coerced value
local function coerce_value(value, schema)
    if value == nil then
        return nil
    end

    local stype = schema.type

    -- handle array type (e.g. ["integer", "null"] from nullable normalization)
    if type(stype) == "table" then
        for _, t in ipairs(stype) do
            if t == "integer" or t == "number" then
                local n = tonumber(value)
                if n then return n end
            elseif t == "boolean" then
                if value == "true" or value == "1" then return true end
                if value == "false" or value == "0" then return false end
            end
        end
        return value
    end

    if stype == "integer" or stype == "number" then
        local n = tonumber(value)
        if n then
            return n
        end
        return value -- let schema validation catch the type error
    elseif stype == "boolean" then
        if value == "true" or value == "1" then
            return true
        elseif value == "false" or value == "0" then
            return false
        end
        return value
    end

    return value
end

--- Coerce values within an object according to its schema properties.
local function coerce_object_values(obj, schema)
    if type(obj) ~= "table" or type(schema) ~= "table" then
        return obj
    end
    local props = schema.properties
    if not props then
        return obj
    end
    for k, v in pairs(obj) do
        if type(v) == "string" and props[k] then
            obj[k] = coerce_value(v, props[k])
        end
    end
    return obj
end

--- Split a string by delimiter.
local function split(s, delim)
    local result = {}
    local from = 1
    local pos
    while true do
        pos = find(s, delim, from, true)
        if not pos then
            insert(result, sub(s, from))
            break
        end
        insert(result, sub(s, from, pos - 1))
        from = pos + 1
    end
    return result
end

--- Parse deepObject style query parameters.
-- deepObject format: param[key]=value or param[key][subkey]=value
-- @param param_name string   the parameter name
-- @param query_args table    all query arguments
-- @param schema table        the parameter schema
-- @return table|nil  parsed nested object
local function parse_deep_object(param_name, query_args, schema)
    local obj = {}
    local prefix = param_name .. "["
    local found = false

    for key, val in pairs(query_args) do
        if sub(key, 1, #prefix) == prefix then
            found = true
            -- extract the bracket path: param[a][b] → {"a", "b"}
            local path = {}
            for bracket_key in key:gmatch("%[([^%]]+)%]") do
                insert(path, bracket_key)
            end

            if #path > 0 then
                local current = obj
                for i = 1, #path - 1 do
                    local p = path[i]
                    if current[p] == nil then
                        current[p] = {}
                    end
                    current = current[p]
                end
                -- use the first value if multiple
                local v = type(val) == "table" and val[1] or val
                current[path[#path]] = v
            end
        end
    end

    if not found then
        return nil
    end

    -- coerce values based on schema properties
    coerce_object_values(obj, schema)

    -- also recurse into nested objects
    if schema.properties then
        for pname, pschema in pairs(schema.properties) do
            if type(obj[pname]) == "table" and pschema.type == "object" then
                coerce_object_values(obj[pname], pschema)
            end
        end
    end

    return obj
end

--- Deserialize a parameter value according to its style and explode settings.
-- See: https://spec.openapis.org/oas/v3.1.0#style-values
--
-- Default styles per location:
--   path: simple, explode=false
--   query: form, explode=true
--   header: simple, explode=false
local function deserialize_param(raw_value, param, query_args)
    local schema = param.schema
    if not schema then
        return raw_value
    end

    local style = param.style
    local explode = param.explode
    local loc = param["in"]

    -- set defaults
    if not style then
        if loc == "query" then
            style = "form"
        else
            style = "simple"
        end
    end
    if explode == nil then
        explode = (style == "form")
    end

    -- handle content-based parameters (param.content.application/json)
    if param.content then
        local json_content = param.content["application/json"]
        if json_content and json_content.schema and has_cjson then
            local decoded = cjson.decode(raw_value)
            if decoded ~= nil then
                return decoded
            end
        end
    end

    local stype = schema.type

    if stype == "array" then
        local items_schema = schema.items or {}
        local values

        if style == "simple" then
            values = split(raw_value, ",")
        elseif style == "form" then
            if not explode then
                values = split(raw_value, ",")
            else
                -- explode=true for query: handled by caller (multiple values)
                if type(raw_value) == "table" then
                    values = raw_value
                else
                    values = { raw_value }
                end
            end
        elseif style == "pipeDelimited" then
            values = split(raw_value, "|")
        elseif style == "spaceDelimited" then
            values = split(raw_value, " ")
        else
            values = { raw_value }
        end

        -- coerce each element
        for i, v in ipairs(values) do
            values[i] = coerce_value(v, items_schema)
        end
        return values

    elseif stype == "object" then
        if style == "deepObject" then
            return parse_deep_object(param.name, query_args or {}, schema)
        end

        -- simple style object: key,value,key,value...
        if style == "simple" and not explode then
            local parts = split(raw_value, ",")
            local obj = {}
            for i = 1, #parts - 1, 2 do
                obj[parts[i]] = parts[i + 1]
            end
            return coerce_object_values(obj, schema)
        elseif style == "simple" and explode then
            -- key=value,key=value
            local parts = split(raw_value, ",")
            local obj = {}
            for _, part in ipairs(parts) do
                local kv = split(part, "=")
                if #kv == 2 then
                    obj[kv[1]] = kv[2]
                end
            end
            return coerce_object_values(obj, schema)
        elseif style == "form" and explode then
            -- explode=true for form+object: each key is a separate query param
            -- handled at higher level
            if type(raw_value) == "table" then
                return coerce_object_values(raw_value, schema)
            end
        end
        return raw_value
    end

    -- scalar
    return coerce_value(raw_value, schema)
end

--- Validate parameters for a matched route.
-- @param route table       matched route from router
-- @param path_params table extracted path parameter values { name = value }
-- @param query_args table  query arguments from request (ngx.req.get_uri_args style)
-- @param headers table     request headers (lowercase keys)
-- @param skip table|nil    { path = bool, query = bool, header = bool }
-- @return boolean
-- @return table|nil  list of error tables
function _M.validate(route, path_params, query_args, headers, skip)
    skip = skip or {}
    query_args = query_args or {}
    headers = headers or {}
    local errs = {}

    local function validate_param_group(param_list, location, raw_values)
        for _, param in ipairs(param_list) do
            local name = param.name
            local style = param.style or (location == "query" and "form" or "simple")
            local raw

            -- deepObject params are parsed from the full query args
            if style == "deepObject" and location == "query" then
                raw = "deepObject_placeholder" -- just a non-nil marker
            else
                raw = raw_values[name]
            end

            -- for headers, try case-insensitive
            if location == "header" and raw == nil then
                raw = raw_values[lower(name)]
            end

            -- check required
            if param.required and (raw == nil or raw == "") then
                -- for deepObject, check if any key with prefix exists
                if style == "deepObject" and location == "query" then
                    local prefix = name .. "["
                    local found = false
                    for k in pairs(query_args) do
                        if sub(k, 1, #prefix) == prefix then
                            found = true
                            break
                        end
                    end
                    if not found then
                        insert(errs, errors.new(location, name,
                            "required parameter is missing"))
                        goto continue
                    end
                else
                    insert(errs, errors.new(location, name,
                        "required parameter is missing"))
                    goto continue
                end
            end

            if raw == nil then
                goto continue
            end

            local schema = param.schema
            if not schema then
                goto continue
            end

            -- deserialize and coerce
            local value = deserialize_param(raw, param, query_args)

            -- validate with jsonschema
            local validator = get_validator(schema)
            if validator then
                local ok, err = validator(value)
                if not ok then
                    local msg = type(err) == "string" and err or "validation failed"
                    insert(errs, errors.new(location, name, msg))
                end
            end

            ::continue::
        end
    end

    if not skip.path and route.params.path then
        validate_param_group(route.params.path, "path", path_params)
    end

    if not skip.query and route.params.query then
        validate_param_group(route.params.query, "query", query_args)
    end

    if not skip.header and route.params.header then
        validate_param_group(route.params.header, "header", headers)
    end

    if #errs > 0 then
        return false, errs
    end
    return true, nil
end

return _M
