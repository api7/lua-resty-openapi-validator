#!/usr/bin/env resty
--- Conformance test ported from kin-openapi issue789_test.go
-- Tests string query params with anyOf/oneOf/allOf pattern constraints (word boundary patterns).
dofile("t/lib/test_bootstrap.lua")

local T = require("test_helper")
local cjson = require("cjson.safe")
local ov = require("resty.openapi_validator")

-- anyOf: string with patterns using word boundary
local anyof_spec = cjson.encode({
    openapi = "3.0.0",
    info = { title = "Sample API", version = "1.0.0" },
    paths = {
        ["/items"] = {
            get = {
                parameters = {
                    {
                        name = "test",
                        ["in"] = "query",
                        required = true,
                        explode = false,
                        schema = {
                            type = "string",
                            anyOf = {
                                { pattern = "\\babc\\b" },
                                { pattern = "\\bfoo\\b" },
                                { pattern = "\\bbar\\b" },
                            },
                        },
                    },
                },
                responses = { ["200"] = { description = "OK" } },
            },
        },
    },
})

-- oneOf version
local oneof_spec = cjson.encode({
    openapi = "3.0.0",
    info = { title = "Sample API", version = "1.0.0" },
    paths = {
        ["/items"] = {
            get = {
                parameters = {
                    {
                        name = "test",
                        ["in"] = "query",
                        required = true,
                        explode = false,
                        schema = {
                            type = "string",
                            oneOf = {
                                { pattern = "\\babc\\b" },
                                { pattern = "\\bfoo\\b" },
                                { pattern = "\\bbar\\b" },
                            },
                        },
                    },
                },
                responses = { ["200"] = { description = "OK" } },
            },
        },
    },
})

-- allOf version
local allof_spec = cjson.encode({
    openapi = "3.0.0",
    info = { title = "Sample API", version = "1.0.0" },
    paths = {
        ["/items"] = {
            get = {
                parameters = {
                    {
                        name = "test",
                        ["in"] = "query",
                        required = true,
                        explode = false,
                        schema = {
                            type = "string",
                            allOf = {
                                { pattern = "\\babc\\b" },
                                { pattern = "\\bfoo\\b" },
                                { pattern = "\\bbar\\b" },
                            },
                        },
                    },
                },
                responses = { ["200"] = { description = "OK" } },
            },
        },
    },
})

local v_anyof = ov.compile(anyof_spec)
local v_oneof = ov.compile(oneof_spec)
local v_allof = ov.compile(allof_spec)
assert(v_anyof and v_oneof and v_allof, "compile failed")

T.describe("issue789: anyOf pattern - 'abc' matches (valid)", function()
    local ok, err = v_anyof:validate_request({
        method = "GET",
        path = "/items",
        query = { test = "abc" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue789: anyOf pattern - 'def' no match (fail)", function()
    local ok, err = v_anyof:validate_request({
        method = "GET",
        path = "/items",
        query = { test = "def" },
    })
    T.ok(not ok, "should fail")
end)

T.describe("issue789: allOf pattern - 'abc foo bar' matches all (valid)", function()
    local ok, err = v_allof:validate_request({
        method = "GET",
        path = "/items",
        query = { test = "abc foo bar" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue789: allOf pattern - 'foo' only matches one (fail)", function()
    local ok, err = v_allof:validate_request({
        method = "GET",
        path = "/items",
        query = { test = "foo" },
    })
    T.ok(not ok, "should fail")
end)

T.describe("issue789: oneOf pattern - 'foo' matches exactly one (valid)", function()
    local ok, err = v_oneof:validate_request({
        method = "GET",
        path = "/items",
        query = { test = "foo" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue789: oneOf pattern - 'def' no match (fail)", function()
    local ok, err = v_oneof:validate_request({
        method = "GET",
        path = "/items",
        query = { test = "def" },
    })
    T.ok(not ok, "should fail")
end)

T.describe("issue789: oneOf pattern - 'foo bar' matches two (fail)", function()
    local ok, err = v_oneof:validate_request({
        method = "GET",
        path = "/items",
        query = { test = "foo bar" },
    })
    T.ok(not ok, "should fail")
end)

T.done()
