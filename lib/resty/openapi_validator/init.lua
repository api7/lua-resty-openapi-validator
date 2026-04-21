local _M = {
    _VERSION = "0.1.0",
}

local loader = require("resty.openapi_validator.loader")
local refs = require("resty.openapi_validator.refs")
local normalize = require("resty.openapi_validator.normalize")
local router_mod = require("resty.openapi_validator.router")
local params_mod = require("resty.openapi_validator.params")
local body_mod = require("resty.openapi_validator.body")
local errors = require("resty.openapi_validator.errors")

local _VMT = {}
_VMT.__index = _VMT

--- Compile an OpenAPI spec string into a validator object.
-- The spec is parsed, $refs resolved, and schemas normalized to Draft 7.
-- The returned table is meant to be cached and reused across requests.
--
-- @param spec_str string  JSON string of an OpenAPI 3.0 or 3.1 spec
-- @param opts table|nil   optional settings:
--   - strict (bool, default true): error on unsupported 3.1 keywords
-- @return table|nil  compiled validator object
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

    -- 5. Build router
    local rtr = router_mod.new(spec)

    return setmetatable({
        spec = spec,
        version = version,
        warnings = warnings,
        _opts = opts,
        _router = rtr,
    }, _VMT), nil
end

--- Validate an incoming HTTP request.
-- @param self table       compiled validator (from compile())
-- @param req table        request data:
--   - method (string, required): HTTP method
--   - path (string, required): request URI path
--   - query (table|nil): query args { name = value|{values} }
--   - headers (table|nil): request headers { name = value }
--   - body (string|nil): raw request body
--   - content_type (string|nil): Content-Type header value
-- @param skip table|nil   { path = bool, query = bool, header = bool, body = bool }
-- @return boolean
-- @return string|nil  formatted error string (kin-openapi compatible)
function _VMT.validate_request(self, req, skip)
    skip = skip or {}

    if not req.method or not req.path then
        return false, "method and path are required"
    end

    -- 1. Route matching
    local route, path_params = self._router:match(req.method, req.path)
    if not route then
        return false, "no matching operation found for "
                      .. req.method .. " " .. req.path
    end

    local all_errs = {}

    -- 2. Parameter validation (path, query, header)
    local param_ok, param_errs = params_mod.validate(
        route, path_params or {},
        req.query or {}, req.headers or {}, skip
    )
    if not param_ok and param_errs then
        for _, e in ipairs(param_errs) do
            all_errs[#all_errs + 1] = e
        end
    end

    -- 3. Body validation
    if not skip.body then
        -- build options for body validation
        local body_opts = {}
        if skip.readOnly ~= nil then
            body_opts.exclude_readonly = skip.readOnly
        end
        if skip.writeOnly ~= nil then
            body_opts.exclude_writeonly = skip.writeOnly
        end

        local body_ok, body_errs = body_mod.validate(
            route, req.body,
            req.content_type or (req.headers and req.headers["content-type"]),
            body_opts
        )
        if not body_ok and body_errs then
            for _, e in ipairs(body_errs) do
                all_errs[#all_errs + 1] = e
            end
        end
    end

    if #all_errs > 0 then
        return false, errors.format(all_errs)
    end

    return true, nil
end

return _M
