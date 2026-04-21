#!/usr/bin/env resty
--- Conformance test ported from kin-openapi issue1110_test.go
-- Tests POST with form-urlencoded body where all properties are optional.
-- Absent optional properties should not cause validation errors.
dofile("t/lib/test_bootstrap.lua")

local T = require("test_helper")
local cjson = require("cjson.safe")
local ov = require("resty.openapi_validator")

local spec = cjson.encode({
    openapi = "3.0.3",
    info = { title = "Test API", version = "1.0.0" },
    paths = {
        ["/test"] = {
            post = {
                requestBody = {
                    content = {
                        ["application/x-www-form-urlencoded"] = {
                            schema = {
                                type = "object",
                                properties = {
                                    param1 = { type = "string" },
                                    param2 = { type = "string" },
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

T.describe("issue1110: empty body (valid - no required fields)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/test",
        body = "",
        content_type = "application/x-www-form-urlencoded",
        headers = { ["content-type"] = "application/x-www-form-urlencoded" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue1110: only param1 present (valid)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/test",
        body = "param1=value1",
        content_type = "application/x-www-form-urlencoded",
        headers = { ["content-type"] = "application/x-www-form-urlencoded" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue1110: only param2 present (valid)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/test",
        body = "param2=value2",
        content_type = "application/x-www-form-urlencoded",
        headers = { ["content-type"] = "application/x-www-form-urlencoded" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue1110: both params present (valid)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/test",
        body = "param1=value1&param2=value2",
        content_type = "application/x-www-form-urlencoded",
        headers = { ["content-type"] = "application/x-www-form-urlencoded" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.done()
