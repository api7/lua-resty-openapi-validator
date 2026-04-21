local cjson   = require("cjson.safe")

local type    = type
local sub_str = string.sub

local _M = {}


-- Parse a JSON string into a Lua table.
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


-- Detect OpenAPI version from parsed spec.
function _M.detect_version(spec)
    local ver = spec.openapi
    if type(ver) ~= "string" then
        return nil, "missing or invalid 'openapi' field"
    end

    if sub_str(ver, 1, 3) == "3.0" then
        return "3.0", nil
    elseif sub_str(ver, 1, 3) == "3.1" then
        return "3.1", nil
    end

    return nil, "unsupported OpenAPI version: " .. ver
end

return _M
