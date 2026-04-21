--- Error types for OpenAPI validation.

local _M = {}

--- Create a validation error.
-- @param location string   "path" | "query" | "header" | "body"
-- @param param string|nil  parameter name (nil for body errors)
-- @param message string    human-readable error
-- @return table
function _M.new(location, param, message)
    return {
        location = location,
        param = param,
        message = message,
    }
end

--- Format a list of errors into a human-readable string.
-- Produces output similar to kin-openapi for compatibility.
-- @param errs table  list of error tables
-- @return string
function _M.format(errs)
    if not errs or #errs == 0 then
        return ""
    end

    local parts = {}
    for _, e in ipairs(errs) do
        local s
        if e.param then
            s = e.location .. " parameter '" .. e.param .. "': " .. e.message
        else
            s = e.location .. ": " .. e.message
        end
        parts[#parts + 1] = s
    end

    return table.concat(parts, "\n")
end

return _M
