local cjson = require("cjson.safe")

local _M = {}

--- Parse a JSON string into a Lua table.
-- @param spec_str string  raw JSON
-- @return table|nil  parsed spec
-- @return string|nil error
function _M.parse(spec_str)
    if type(spec_str) ~= "string" or #spec_str == 0 then
        return nil, "spec must be a non-empty string"
    end

    local spec, err = cjson.decode(spec_str)
    if not spec then
        return nil, "invalid JSON: " .. (err or "decode error")
    end

    return spec, nil
end

--- Detect OpenAPI version from parsed spec.
-- @param spec table  parsed OpenAPI document
-- @return string|nil  "3.0" or "3.1"
-- @return string|nil  error message
function _M.detect_version(spec)
    local ver = spec.openapi
    if type(ver) ~= "string" then
        return nil, "missing or invalid 'openapi' field"
    end

    if ver:sub(1, 3) == "3.0" then
        return "3.0", nil
    elseif ver:sub(1, 3) == "3.1" then
        return "3.1", nil
    end

    return nil, "unsupported OpenAPI version: " .. ver
end

return _M
