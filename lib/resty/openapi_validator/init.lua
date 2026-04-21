local _M = {
    _VERSION = "0.1.0",
}

local loader = require("resty.openapi_validator.loader")
local refs = require("resty.openapi_validator.refs")
local normalize = require("resty.openapi_validator.normalize")

--- Compile an OpenAPI spec string into a validator object.
-- The spec is parsed, $refs resolved, and schemas normalized to Draft 7.
-- The returned table is meant to be cached and reused across requests.
--
-- @param spec_str string  JSON string of an OpenAPI 3.0 or 3.1 spec
-- @param opts table|nil   optional settings:
--   - strict (bool, default true): error on unsupported 3.1 keywords
-- @return table|nil  compiled spec context (passed to validate_request later)
-- @return string|nil error message
function _M.compile(spec_str, opts)
    opts = opts or {}
    if opts.strict == nil then
        opts.strict = true
    end

    -- 1. Parse JSON
    local spec, err = loader.parse(spec_str)
    if not spec then
        return nil, "failed to parse spec: " .. (err or "unknown error")
    end

    -- 2. Detect version
    local version, err = loader.detect_version(spec)
    if not version then
        return nil, err
    end

    -- 3. Resolve internal $refs
    local ok, err = refs.resolve(spec)
    if not ok then
        return nil, "failed to resolve $ref: " .. err
    end

    -- 4. Normalize schemas to Draft 7
    local warnings
    warnings, err = normalize.normalize_spec(spec, version, opts)
    if err then
        return nil, "normalization error: " .. err
    end

    return {
        spec = spec,
        version = version,
        warnings = warnings,
        _opts = opts,
    }, nil
end

return _M
