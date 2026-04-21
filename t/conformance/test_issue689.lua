#!/usr/bin/env resty
--- Conformance test ported from kin-openapi issue689_test.go
-- Tests readOnly/writeOnly property validation in request bodies.
-- Note: writeOnly validation is for RESPONSE bodies (not requests), so we only test readOnly here.
dofile("t/lib/test_bootstrap.lua")

local T = require("test_helper")
local cjson = require("cjson.safe")
local ov = require("resty.openapi_validator")

local spec = cjson.encode({
    openapi = "3.0.0",
    info = { title = "Sample API", version = "1.0.0" },
    paths = {
        ["/items"] = {
            put = {
                requestBody = {
                    content = {
                        ["application/json"] = {
                            schema = {
                                type = "object",
                                properties = {
                                    testWithReadOnly = { readOnly = true, type = "boolean" },
                                    testNoReadOnly = { type = "boolean" },
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

T.describe("issue689: non read-only property in request (valid)", function()
    local ok, err = v:validate_request({
        method = "PUT",
        path = "/items",
        body = '{"testNoReadOnly": true}',
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue689: non read-only property, validation disabled (valid)", function()
    local ok, err = v:validate_request({
        method = "PUT",
        path = "/items",
        body = '{"testNoReadOnly": true}',
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    }, { readOnly = true })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue689: read-only property in request (fail)", function()
    local ok, err = v:validate_request({
        method = "PUT",
        path = "/items",
        body = '{"testWithReadOnly": true}',
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    })
    T.ok(not ok, "should fail")
    T.ok(err and err:find("readOnly", 1, true), "error should mention readOnly: " .. tostring(err))
end)

T.describe("issue689: read-only property, validation disabled (valid)", function()
    local ok, err = v:validate_request({
        method = "PUT",
        path = "/items",
        body = '{"testWithReadOnly": true}',
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    }, { readOnly = true })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.done()
