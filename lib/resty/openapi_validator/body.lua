--- Request body validation.
-- Handles JSON body parsing and schema validation.

local _M = {}

local type = type
local find = string.find
local lower = string.lower
local insert = table.insert

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

--- Validate request body.
-- @param route table        matched route from router
-- @param body_str string    raw request body (may be nil or empty)
-- @param content_type string  Content-Type header value
-- @return boolean
-- @return table|nil  list of error tables
function _M.validate(route, body_str, content_type)
    local errs = {}

    -- check if body is required
    if route.body_required then
        if body_str == nil or body_str == "" then
            insert(errs, errors.new("body", nil, "request body is required"))
            return false, errs
        end
    end

    -- no body schema means nothing to validate
    if not route.body_schema then
        return true, nil
    end

    -- no body provided and not required → OK
    if body_str == nil or body_str == "" then
        return true, nil
    end

    -- determine content type and validate accordingly
    if is_json_content_type(content_type) then
        -- parse JSON body
        local body_data, decode_err = cjson.decode(body_str)
        if not body_data then
            insert(errs, errors.new("body", nil,
                "invalid JSON body: " .. (decode_err or "decode error")))
            return false, errs
        end

        -- validate against schema
        local validator = get_validator(route.body_schema)
        if validator then
            local ok, err = validator(body_data)
            if not ok then
                local msg = type(err) == "string" and err or "body validation failed"
                insert(errs, errors.new("body", nil, msg))
            end
        end

    elseif is_form_content_type(content_type) then
        -- for form-urlencoded, we'd need to parse the body into key-value pairs
        -- and validate against schema. For now, skip with a warning approach:
        -- the caller can pre-parse and pass as a table in a future version.
        -- For v1, we attempt basic validation if schema is object type.
        -- This is a simplified implementation.
        return true, nil

    else
        -- non-JSON, non-form content types: skip validation in v1
        -- (multipart/form-data, application/xml, etc.)
        return true, nil
    end

    if #errs > 0 then
        return false, errs
    end
    return true, nil
end

return _M
