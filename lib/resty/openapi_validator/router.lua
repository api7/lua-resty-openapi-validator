--- Router: maps incoming (method, path) to OpenAPI operations.
-- Uses lua-resty-radixtree for high-performance path matching.
-- Converts OpenAPI path templates ({param}) to radixtree :param syntax.

local _M = {}
local _MT = { __index = _M }

local radixtree = require("resty.radixtree")

local type = type
local pairs = pairs
local ipairs = ipairs
local insert = table.insert
local find = string.find
local sub = string.sub
local gsub = string.gsub
local byte = string.byte

local SLASH = byte("/")

local HTTP_METHODS = {
    GET = true, POST = true, PUT = true, DELETE = true,
    PATCH = true, HEAD = true, OPTIONS = true, TRACE = true,
}

--- Convert OpenAPI path template to radixtree format.
-- e.g. "/users/{id}/posts/{postId}" → "/users/:id/posts/:postId"
local function convert_path(path_template)
    return (gsub(path_template, "{([^}]+)}", ":_%1"))
end

--- Extract param names from {param} in path template.
local function extract_param_names(path_template)
    local names = {}
    for name in path_template:gmatch("{([^}]+)}") do
        insert(names, name)
    end
    return names
end

--- Collect and organize parameters for an operation.
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
            insert(by_loc[loc], p)
        end
    end
    return by_loc
end

--- Find request body schema and content map.
local function find_body_info(operation)
    if not operation.requestBody then
        return nil, nil, false
    end
    local body_required = operation.requestBody.required or false
    local content = operation.requestBody.content
    if not content then
        return nil, nil, body_required
    end

    -- find the primary schema (prefer JSON)
    local primary_schema
    if content["application/json"] then
        primary_schema = content["application/json"].schema
    else
        for ct, media in pairs(content) do
            if ct == "*/*" or find(ct, "json") then
                primary_schema = media.schema
                break
            end
        end
        if not primary_schema then
            for _, media in pairs(content) do
                primary_schema = media.schema
                break
            end
        end
    end

    return primary_schema, content, body_required
end

--- Build a router from a compiled OpenAPI spec.
-- @param spec table  the parsed+normalized spec (with paths)
-- @return table  router object
function _M.new(spec)
    local radix_routes = {}
    local route_metadata = {} -- id → route detail

    local paths = spec.paths
    if not paths then
        return setmetatable({ rx = nil, metadata = route_metadata }, _MT)
    end

    local route_id = 0
    for path_template, path_item in pairs(paths) do
        local radix_path = convert_path(path_template)
        local param_names = extract_param_names(path_template)

        for method, operation in pairs(path_item) do
            local m = method:upper()
            if HTTP_METHODS[m] then
                route_id = route_id + 1
                local id = tostring(route_id)

                local params = collect_params(path_item, operation)
                local body_schema, body_content, body_required = find_body_info(operation)

                route_metadata[id] = {
                    path_template = path_template,
                    param_names = param_names,
                    method = m,
                    operation = operation,
                    params = params,
                    body_schema = body_schema,
                    body_content = body_content,
                    body_required = body_required,
                }

                insert(radix_routes, {
                    paths = { radix_path },
                    methods = { m },
                    metadata = id,
                })
            end
        end
    end

    if #radix_routes == 0 then
        return setmetatable({ rx = nil, metadata = route_metadata }, _MT)
    end

    local rx = radixtree.new(radix_routes)
    return setmetatable({ rx = rx, metadata = route_metadata }, _MT)
end

--- Match an incoming request to a route.
-- @param method string  HTTP method (uppercase)
-- @param path string    request URI path (without query string)
-- @return table|nil  matched route (with params, body_schema, etc.)
-- @return table|nil  extracted path parameters { name = value }
function _M.match(self, method, path)
    if not self.rx then
        return nil, nil
    end

    method = method:upper()

    -- strip query string if present
    local qpos = find(path, "?", 1, true)
    if qpos then
        path = sub(path, 1, qpos - 1)
    end

    -- normalize: remove trailing slash (except root)
    if #path > 1 and byte(path, #path) == SLASH then
        path = sub(path, 1, #path - 1)
    end

    local matched = {}
    local opts = {
        method = method,
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
