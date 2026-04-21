local _M = {version = 0.1}

local loader     = require("resty.openapi_validator.loader")
local refs       = require("resty.openapi_validator.refs")
local normalize  = require("resty.openapi_validator.normalize")
local router_mod = require("resty.openapi_validator.router")
local params_mod = require("resty.openapi_validator.params")
local body_mod   = require("resty.openapi_validator.body")
local errors     = require("resty.openapi_validator.errors")

local setmetatable = setmetatable
local ipairs       = ipairs

local _validator_mt = {}
_validator_mt.__index = _validator_mt


-- Compile an OpenAPI spec string into a validator object.
-- The spec is parsed, $refs resolved, and schemas normalized to Draft 7.
-- The returned table is meant to be cached and reused across requests.
function _M.compile(spec_str, opts)
    opts = opts or {}
    if opts.strict == nil then
        opts.strict = true
    end

    local spec, err = loader.parse(spec_str)
    if not spec then
        return nil, "failed to parse spec: " .. (err or "unknown error")
    end

    local version
    version, err = loader.detect_version(spec)
    if not version then
        return nil, err
    end

    local ok
    ok, err = refs.resolve(spec)
    if not ok then
        return nil, "failed to resolve $ref: " .. err
    end

    local warnings
    warnings, err = normalize.normalize_spec(spec, version, opts)
    if err then
        return nil, "normalization error: " .. err
    end

    local rtr = router_mod.new(spec)

    return setmetatable({
        spec     = spec,
        version  = version,
        warnings = warnings,
        _opts    = opts,
        _router  = rtr,
    }, _validator_mt), nil
end


-- Validate an incoming HTTP request.
function _validator_mt.validate_request(self, req, skip)
    skip = skip or {}

    if not req.method or not req.path then
        return false, "method and path are required"
    end

    local route, path_params = self._router:match(req.method, req.path)
    if not route then
        return false, "no matching operation found for "
                      .. req.method .. " " .. req.path
    end

    local all_errs = {}

    local param_ok, param_errs = params_mod.validate(
        route, path_params or {},
        req.query or {}, req.headers or {}, skip
    )
    if not param_ok and param_errs then
        for _, e in ipairs(param_errs) do
            all_errs[#all_errs + 1] = e
        end
    end

    if not skip.body then
        local body_opts = {}
        if skip.read_only ~= nil then
            body_opts.exclude_readonly = skip.read_only
        end
        if skip.write_only ~= nil then
            body_opts.exclude_writeonly = skip.write_only
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
