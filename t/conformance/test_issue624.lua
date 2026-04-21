#!/usr/bin/env resty
--- Conformance test ported from kin-openapi issue624_test.go
-- Tests content-encoded query parameters with anyOf (non-object types).
dofile("t/lib/test_bootstrap.lua")

local T = require("test_helper")
local cjson = require("cjson.safe")
local ov = require("resty.openapi_validator")

local spec = cjson.encode({
    openapi = "3.0.0",
    info = { title = "Sample API", version = "1.0.0" },
    paths = {
        ["/items"] = {
            get = {
                parameters = {
                    {
                        name = "test",
                        ["in"] = "query",
                        required = false,
                        explode = true,
                        style = "form",
                        content = {
                            ["application/json"] = {
                                schema = {
                                    anyOf = {
                                        { type = "string" },
                                        { type = "integer" },
                                    },
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

T.describe("issue624: content query param 'test1' (valid string)", function()
    local ok, err = v:validate_request({
        method = "GET",
        path = "/items",
        query = { test = "test1" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue624: content query param 'test[1' (valid string)", function()
    local ok, err = v:validate_request({
        method = "GET",
        path = "/items",
        query = { test = "test[1" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.done()
