#!/usr/bin/env luajit
--- Tests for router.lua
package.path = "lib/?.lua;lib/?/init.lua;t/lib/?.lua;;" .. package.path

local T = require("test_helper")
local cjson = require("cjson.safe")
local router_mod = require("resty.openapi_validator.router")

local function load_spec(filename)
    local f = io.open("t/specs/" .. filename, "r")
    assert(f, "cannot open " .. filename)
    local data = f:read("*a")
    f:close()
    return cjson.decode(data)
end

-- Test: basic path matching
T.describe("router: basic GET match", function()
    local spec = load_spec("basic_30.json")
    -- resolve refs first
    local refs = require("resty.openapi_validator.refs")
    refs.resolve(spec)

    local router = router_mod.new(spec)

    local route, params = router:match("GET", "/users/42")
    T.ok(route ~= nil, "GET /users/42 matched")
    T.is(route.method, "GET", "method is GET")
    T.is(params.id, "42", "path param id=42")
end)

-- Test: POST match
T.describe("router: POST match", function()
    local spec = load_spec("basic_30.json")
    local refs = require("resty.openapi_validator.refs")
    refs.resolve(spec)

    local router = router_mod.new(spec)

    local route, params = router:match("POST", "/users/123")
    T.ok(route ~= nil, "POST /users/123 matched")
    T.is(route.method, "POST", "method is POST")
    T.ok(route.body_schema ~= nil, "body schema present")
    T.is(route.body_schema.type, "object", "body schema is object")
end)

-- Test: method mismatch
T.describe("router: method mismatch", function()
    local spec = load_spec("basic_30.json")
    local refs = require("resty.openapi_validator.refs")
    refs.resolve(spec)

    local router = router_mod.new(spec)

    local route = router:match("DELETE", "/users/42")
    T.ok(route == nil, "DELETE /users/42 not matched")
end)

-- Test: path not found
T.describe("router: path not found", function()
    local spec = load_spec("basic_30.json")
    local refs = require("resty.openapi_validator.refs")
    refs.resolve(spec)

    local router = router_mod.new(spec)

    local route = router:match("GET", "/nonexistent")
    T.ok(route == nil, "/nonexistent not matched")
end)

-- Test: trailing slash normalization
T.describe("router: trailing slash", function()
    local spec = load_spec("basic_30.json")
    local refs = require("resty.openapi_validator.refs")
    refs.resolve(spec)

    local router = router_mod.new(spec)

    local route, params = router:match("GET", "/users/42/")
    T.ok(route ~= nil, "GET /users/42/ matched (trailing slash stripped)")
    T.is(params.id, "42", "param extracted correctly")
end)

-- Test: percent-encoded path
T.describe("router: percent-encoded path", function()
    local spec = load_spec("basic_30.json")
    local refs = require("resty.openapi_validator.refs")
    refs.resolve(spec)

    local router = router_mod.new(spec)

    local route, params = router:match("GET", "/users/hello%20world")
    T.ok(route ~= nil, "percent-encoded path matched")
    T.is(params.id, "hello world", "percent decoding works")
end)

-- Test: query string stripped
T.describe("router: query string stripped", function()
    local spec = load_spec("basic_30.json")
    local refs = require("resty.openapi_validator.refs")
    refs.resolve(spec)

    local router = router_mod.new(spec)

    local route, params = router:match("GET", "/users/42?limit=10")
    T.ok(route ~= nil, "path with query matched")
    T.is(params.id, "42", "param extracted ignoring query")
end)

-- Test: route has organized parameters
T.describe("router: params organized by location", function()
    local spec = load_spec("basic_30.json")
    local refs = require("resty.openapi_validator.refs")
    refs.resolve(spec)

    local router = router_mod.new(spec)

    local route = router:match("GET", "/users/42")
    T.ok(route.params ~= nil, "params table exists")
    T.ok(route.params.path ~= nil, "path params exist")
    T.ok(route.params.query ~= nil, "query params exist")

    -- check path param
    local found_id = false
    for _, p in ipairs(route.params.path) do
        if p.name == "id" then found_id = true end
    end
    T.ok(found_id, "id found in path params")

    -- check query param
    local found_limit = false
    for _, p in ipairs(route.params.query) do
        if p.name == "limit" then found_limit = true end
    end
    T.ok(found_limit, "limit found in query params")
end)

-- Test: no paths in spec
T.describe("router: empty spec", function()
    local router = router_mod.new({ paths = {} })
    local route = router:match("GET", "/anything")
    T.ok(route == nil, "no routes in empty spec")
end)

-- Test: multiple path params
T.describe("router: multiple path params", function()
    local spec = {
        paths = {
            ["/orgs/{orgId}/users/{userId}"] = {
                get = {
                    parameters = {
                        { name = "orgId", ["in"] = "path", required = true,
                          schema = { type = "string" } },
                        { name = "userId", ["in"] = "path", required = true,
                          schema = { type = "integer" } },
                    },
                    responses = { ["200"] = { description = "OK" } },
                }
            }
        }
    }
    local router = router_mod.new(spec)

    local route, params = router:match("GET", "/orgs/api7/users/99")
    T.ok(route ~= nil, "multi-param path matched")
    T.is(params.orgId, "api7", "orgId extracted")
    T.is(params.userId, "99", "userId extracted")
end)

-- Test: body_required flag
T.describe("router: body_required", function()
    local spec = load_spec("basic_30.json")
    local refs = require("resty.openapi_validator.refs")
    refs.resolve(spec)
    local router = router_mod.new(spec)

    local route = router:match("POST", "/users/42")
    T.ok(route.body_required == true, "body_required is true for POST /users/{id}")

    local route2 = router:match("GET", "/users/42")
    T.ok(route2.body_required == false, "body_required is false for GET")
end)

T.done()
