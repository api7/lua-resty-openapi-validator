-- Router: maps incoming (method, path) to OpenAPI operations.
-- Uses lua-resty-radixtree for high-performance path matching.
-- Converts OpenAPI path templates ({param}) to radixtree :param syntax.

local _M = {}

local radixtree = require("resty.radixtree")

local setmetatable = setmetatable
local tostring     = tostring
local pairs        = pairs
local ipairs       = ipairs
local tab_insert   = table.insert
local str_find     = string.find
local sub_str      = string.sub
local str_gsub     = string.gsub
local str_byte     = string.byte
local str_upper    = string.upper
local str_lower    = string.lower
local str_gmatch   = string.gmatch

local SLASH = str_byte("/")

local HTTP_METHODS = {
    GET = true, POST = true, PUT = true, DELETE = true,
    PATCH = true, HEAD = true, OPTIONS = true, TRACE = true,
}

local _router_mt = { __index = _M }


-- Convert OpenAPI path template to radixtree format.
-- e.g. "/users/{id}/posts/{postId}" -> "/users/:id/posts/:postId"
local function convert_path(path_template)
    return (str_gsub(path_template, "{([^}]+)}", ":_%1"))
end


-- Extract param names from {param} in path template.
local function extract_param_names(path_template)
    local names = {}
    for name in str_gmatch(path_template, "{([^}]+)}") do
        tab_insert(names, name)
    end
    return names
end


-- Collect and organize parameters for an operation.
local function collect_params(path_item, operation)
    local all_params = {}
    if path_item.parameters then
        for _, p in ipairs(path_item.parameters) do
            all_params[p.name .. ":" .. p["in"]] = p
        end
    end
    if operation.parameters then
        for _, p in ipairs(operation.parameters) do
            all_params[p.name .. ":" .. p["in"]] = p
        end
    end

    local by_loc = { path = {}, query = {}, header = {} }
    for _, p in pairs(all_params) do
        local loc = p["in"]
        if by_loc[loc] then
            tab_insert(by_loc[loc], p)
        end
    end
    return by_loc
end


-- Find request body schema and content map.
local function find_body_info(operation)
    if not operation.requestBody then
        return nil, nil, false
    end
    local body_required = operation.requestBody.required or false
    local content = operation.requestBody.content
    if not content then
        return nil, nil, body_required
    end

    local primary_schema
    if content["application/json"] then
        primary_schema = content["application/json"].schema
    else
        for ct, media in pairs(content) do
            local ct_lower = str_lower(ct)
            if ct == "*/*" or str_find(ct_lower, "json", 1, true) then
                primary_schema = media.schema
                break
            end
        end
        if not primary_schema then
            -- pick the first available schema as fallback
            for _, media in pairs(content) do  -- luacheck: ignore 512
                primary_schema = media.schema
                break
            end
        end
    end

    return primary_schema, content, body_required
end


-- Extract base paths from the servers array.
-- Returns a list of base path prefixes (empty string if none).
local function extract_base_paths(spec)
    local servers = spec.servers
    if not servers or #servers == 0 then
        return { "" }
    end

    local bases = {}
    for _, srv in ipairs(servers) do
        local url = srv.url or ""
        -- strip protocol+host if present, keep only the path portion
        local path = url:match("^https?://[^/]*(/.*)$") or url
        -- remove trailing slash
        if #path > 1 and str_byte(path, #path) == SLASH then
            path = sub_str(path, 1, #path - 1)
        end
        -- "/" means no prefix
        if path == "/" then
            path = ""
        end
        bases[#bases + 1] = path
    end

    if #bases == 0 then
        return { "" }
    end
    return bases
end


-- Build a router from a compiled OpenAPI spec.
function _M.new(spec)
    local radix_routes = {}
    local route_metadata = {}

    local paths = spec.paths
    if not paths then
        return setmetatable({ rx = nil, metadata = route_metadata }, _router_mt)
    end

    local base_paths = extract_base_paths(spec)

    local route_id = 0
    for path_template, path_item in pairs(paths) do
        local param_names = extract_param_names(path_template)

        for method, operation in pairs(path_item) do
            local m = str_upper(method)
            if HTTP_METHODS[m] then
                route_id = route_id + 1
                local id = tostring(route_id)

                local params = collect_params(path_item, operation)
                local body_schema, body_content, body_required =
                    find_body_info(operation)

                route_metadata[id] = {
                    path_template = path_template,
                    param_names   = param_names,
                    method        = m,
                    operation     = operation,
                    params        = params,
                    body_schema   = body_schema,
                    body_content  = body_content,
                    body_required = body_required,
                }

                local route_paths = {}
                for _, base in ipairs(base_paths) do
                    route_paths[#route_paths + 1] =
                        convert_path(base .. path_template)
                end

                tab_insert(radix_routes, {
                    paths    = route_paths,
                    methods  = { m },
                    metadata = id,
                })
            end
        end
    end

    if #radix_routes == 0 then
        return setmetatable({ rx = nil, metadata = route_metadata }, _router_mt)
    end

    local rx = radixtree.new(radix_routes)
    return setmetatable({ rx = rx, metadata = route_metadata }, _router_mt)
end


-- Match an incoming request to a route.
function _M.match(self, method, path)
    if not self.rx then
        return nil, nil
    end

    method = str_upper(method)

    -- strip query string if present
    local qpos = str_find(path, "?", 1, true)
    if qpos then
        path = sub_str(path, 1, qpos - 1)
    end

    -- normalize: remove trailing slash (except root)
    if #path > 1 and str_byte(path, #path) == SLASH then
        path = sub_str(path, 1, #path - 1)
    end

    local matched = {}
    local opts = {
        method  = method,
        matched = matched,
    }

    local id = self.rx:match(path, opts)
    if not id then
        return nil, nil
    end

    local route = self.metadata[id]
    if not route then
        return nil, nil
    end

    -- extract path params from radixtree matched table
    -- radixtree stores them with "_" prefix since we use :_paramName
    local path_params = {}
    for _, name in ipairs(route.param_names) do
        path_params[name] = matched["_" .. name]
    end

    return route, path_params
end

return _M
