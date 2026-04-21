#!/usr/bin/env resty
--- Conformance test ported from kin-openapi issue201_test.go
-- Tests duplicate path templates with different methods and overlapping path segments.
dofile("t/lib/test_bootstrap.lua")

local T = require("test_helper")
local cjson = require("cjson.safe")
local ov = require("resty.openapi_validator")

local spec = cjson.encode({
    openapi = "3.0.0",
    info = { title = "Sample API", version = "1.0.0" },
    paths = {
        ["/users/{id}"] = {
            get = {
                parameters = {
                    { name = "id", ["in"] = "path", required = true,
                      schema = { type = "string" } },
                },
                responses = { ["200"] = { description = "OK" } },
            },
            post = {
                parameters = {
                    { name = "id", ["in"] = "path", required = true,
                      schema = { type = "string" } },
                },
                requestBody = {
                    required = true,
                    content = {
                        ["application/json"] = {
                            schema = {
                                type = "object",
                                required = { "name" },
                                properties = {
                                    name = { type = "string" },
                                },
                            },
                        },
                    },
                },
                responses = { ["200"] = { description = "OK" } },
            },
        },
    },
})

local v = ov.compile(spec)
assert(v, "compile failed")

T.describe("issue201: GET /users/123 (valid)", function()
    local ok, err = v:validate_request({
        method = "GET",
        path = "/users/123",
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue201: POST /users/123 with valid body (valid)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/users/123",
        body = '{"name": "alice"}',
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue201: POST /users/123 missing required body field (fail)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/users/123",
        body = '{}',
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    })
    T.ok(not ok, "should fail - missing required field 'name'")
end)

T.describe("issue201: GET /users/abc string id (valid)", function()
    local ok, err = v:validate_request({
        method = "GET",
        path = "/users/abc",
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.done()
