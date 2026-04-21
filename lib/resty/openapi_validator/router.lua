--- Router: maps incoming (method, path) to OpenAPI operations.
-- Converts OpenAPI path templates ({param}) to match patterns,
-- indexes by method, extracts path parameters.

local _M = {}
local _MT = { __index = _M }

local type = type
local pairs = pairs
local ipairs = ipairs
local insert = table.insert
local find = string.find
local sub = string.sub
local gsub = string.gsub
local match = string.match
local byte = string.byte

local SLASH = byte("/")

--- Convert OpenAPI path template to a Lua pattern + param name list.
-- e.g. "/users/{id}/posts/{postId}" → "^/users/([^/]+)/posts/([^/]+)$", {"id", "postId"}
local function compile_path(path_template)
    local params = {}
    -- Escape Lua pattern special chars except { }
    local pattern = gsub(path_template, "([%.%+%-%*%?%[%]%^%$%(%)%%])", "%%%1")
    -- Replace {param} with capture group
    pattern = gsub(pattern, "{([^}]+)}", function(name)
        insert(params, name)
        return "([^/]+)"
    end)
    return "^" .. pattern .. "$", params
end

--- Percent-decode a URL segment.
local function percent_decode(s)
    return gsub(s, "%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
end

--- Build a router from a compiled OpenAPI spec.
-- @param spec table  the parsed+normalized spec (with paths)
-- @return table  router object
function _M.new(spec)
    local routes = {}

    local paths = spec.paths
    if not paths then
        return setmetatable({ routes = routes }, _MT)
    end

    for path_template, path_item in pairs(paths) do
        local pattern, param_names = compile_path(path_template)

        for method, operation in pairs(path_item) do
            -- skip non-operation keys (parameters, summary, etc.)
            local m = method:upper()
            if m == "GET" or m == "POST" or m == "PUT" or m == "DELETE"
               or m == "PATCH" or m == "HEAD" or m == "OPTIONS"
               or m == "TRACE" then

                -- collect parameters from path-level and operation-level
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

                -- organize params by location
                local params_by_loc = {
                    path = {},
                    query = {},
                    header = {},
                }
                for _, p in pairs(all_params) do
                    local loc = p["in"]
                    if params_by_loc[loc] then
                        insert(params_by_loc[loc], p)
                    end
                end

                -- find request body schema (prefer application/json)
                local body_schema, body_required
                if operation.requestBody then
                    body_required = operation.requestBody.required
                    local content = operation.requestBody.content
                    if content then
                        if content["application/json"] then
                            body_schema = content["application/json"].schema
                        else
                            -- try wildcard or first available
                            for ct, media in pairs(content) do
                                if ct == "*/*" or find(ct, "json") then
                                    body_schema = media.schema
                                    break
                                end
                            end
                            if not body_schema then
                                -- take first content type
                                for _, media in pairs(content) do
                                    body_schema = media.schema
                                    break
                                end
                            end
                        end
                    end
                end

                insert(routes, {
                    path_template = path_template,
                    pattern = pattern,
                    param_names = param_names,
                    method = m,
                    operation = operation,
                    params = params_by_loc,
                    body_schema = body_schema,
                    body_required = body_required or false,
                })
            end
        end
    end

    return setmetatable({ routes = routes }, _MT)
end

--- Match an incoming request to a route.
-- @param method string  HTTP method (uppercase)
-- @param path string    request URI path (without query string)
-- @return table|nil  matched route
-- @return table|nil  extracted path parameters { name = value }
function _M.match(self, method, path)
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

    -- percent-decode the path
    path = percent_decode(path)

    for _, route in ipairs(self.routes) do
        if route.method == method then
            local captures = { match(path, route.pattern) }
            if #captures > 0 or (path == route.path_template and #route.param_names == 0) then
                -- for paths without params, check exact match
                if #route.param_names == 0 then
                    if path:match(route.pattern) then
                        return route, {}
                    end
                else
                    local path_params = {}
                    for i, name in ipairs(route.param_names) do
                        path_params[name] = captures[i]
                    end
                    return route, path_params
                end
            end
        end
    end

    return nil, nil
end

return _M
