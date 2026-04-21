#!/usr/bin/env resty
--- Conformance test ported from kin-openapi issue733_test.go (TestIntMax)
-- Tests large integer (int64) values in request body.
dofile("t/lib/test_bootstrap.lua")

local T = require("test_helper")
local cjson = require("cjson.safe")
local ov = require("resty.openapi_validator")

local spec = cjson.encode({
    openapi = "3.0.0",
    info = { title = "test large integer value", version = "1.0.0" },
    paths = {
        ["/test"] = {
            post = {
                requestBody = {
                    content = {
                        ["application/json"] = {
                            schema = {
                                type = "object",
                                properties = {
                                    testInteger = { type = "integer", format = "int64" },
                                    testDefault = { type = "boolean" },
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

T.describe("issue733: max int64 value (valid)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/test",
        body = '{"testInteger": 9223372036854775807}',
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue733: min int64 value (valid)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/test",
        body = '{"testInteger": -9223372036854775808}',
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.done()
