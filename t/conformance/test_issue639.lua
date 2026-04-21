#!/usr/bin/env resty
--- Conformance test ported from kin-openapi issue639_test.go
-- Tests request body decode edge cases: empty objects, optional bodies,
-- additional properties, and nested object validation.
dofile("t/lib/test_bootstrap.lua")

local T = require("test_helper")
local cjson = require("cjson.safe")
local ov = require("resty.openapi_validator")

local spec = cjson.encode({
    openapi = "3.0.0",
    info = { title = "Sample API", version = "1.0.0" },
    paths = {
        ["/items"] = {
            post = {
                requestBody = {
                    required = false,
                    content = {
                        ["application/json"] = {
                            schema = {
                                type = "object",
                                properties = {
                                    name = { type = "string" },
                                    count = { type = "integer" },
                                    metadata = {
                                        type = "object",
                                        properties = {
                                            tags = {
                                                type = "array",
                                                items = { type = "string" },
                                            },
                                            nested = {
                                                type = "object",
                                                properties = {
                                                    level = { type = "integer" },
                                                },
                                            },
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
                responses = { ["200"] = { description = "OK" } },
            },
        },
        ["/strict"] = {
            post = {
                requestBody = {
                    required = true,
                    content = {
                        ["application/json"] = {
                            schema = {
                                type = "object",
                                required = { "id" },
                                properties = {
                                    id = { type = "integer" },
                                    label = { type = "string" },
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

T.describe("issue639: empty object with only optional properties (valid)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/items",
        body = "{}",
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue639: no body when body is not required (valid)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/items",
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue639: object with all fields (valid)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/items",
        body = '{"name": "widget", "count": 5}',
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue639: object with additional properties (valid - no restriction)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/items",
        body = '{"name": "widget", "extra_field": "hello", "another": 42}',
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue639: deeply nested valid object (valid)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/items",
        body = '{"name": "widget", "metadata": {"tags": ["a", "b"], "nested": {"level": 3}}}',
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue639: missing required field in /strict (fail)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/strict",
        body = '{"label": "test"}',
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    })
    T.ok(not ok, "should fail - missing required field 'id'")
end)

T.describe("issue639: valid required field in /strict (valid)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/strict",
        body = '{"id": 1, "label": "test"}',
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.done()
