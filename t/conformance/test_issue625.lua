#!/usr/bin/env resty
--- Conformance test ported from kin-openapi issue625_test.go
-- Tests array query params with anyOf/oneOf/allOf items.
dofile("t/lib/test_bootstrap.lua")

local T = require("test_helper")
local cjson = require("cjson.safe")
local ov = require("resty.openapi_validator")

-- anyOf: items are anyOf integer | boolean
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
                        required = false,
                        explode = false,
                        schema = {
                            type = "array",
                            items = {
                                anyOf = {
                                    { type = "integer" },
                                    { type = "boolean" },
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

-- allOf: items are allOf integer & number
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
                        required = false,
                        explode = false,
                        schema = {
                            type = "array",
                            items = {
                                allOf = {
                                    { type = "integer" },
                                    { type = "number" },
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

-- oneOf: items are oneOf integer | boolean
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
                        required = false,
                        explode = false,
                        schema = {
                            type = "array",
                            items = {
                                oneOf = {
                                    { type = "integer" },
                                    { type = "boolean" },
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

local v_anyof = ov.compile(anyof_spec)
local v_allof = ov.compile(allof_spec)
local v_oneof = ov.compile(oneof_spec)
assert(v_anyof and v_allof and v_oneof, "compile failed")

T.describe("issue625: anyOf array - integers (valid)", function()
    local ok, err = v_anyof:validate_request({
        method = "GET",
        path = "/items",
        query = { test = "3,7" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue625: anyOf array - strings (fail)", function()
    local ok, err = v_anyof:validate_request({
        method = "GET",
        path = "/items",
        query = { test = "s1,s2" },
    })
    T.ok(not ok, "should fail")
end)

T.describe("issue625: allOf array - integers (valid)", function()
    local ok, err = v_allof:validate_request({
        method = "GET",
        path = "/items",
        query = { test = "1,3" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue625: allOf array - floats (fail)", function()
    local ok, err = v_allof:validate_request({
        method = "GET",
        path = "/items",
        query = { test = "1.2,3.1" },
    })
    T.ok(not ok, "should fail")
end)

T.describe("issue625: oneOf array - mixed bool+int (valid)", function()
    local ok, err = v_oneof:validate_request({
        method = "GET",
        path = "/items",
        query = { test = "true,3" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue625: oneOf array - quoted strings (fail)", function()
    -- quoted strings don't match integer or boolean
    local ok, err = v_oneof:validate_request({
        method = "GET",
        path = "/items",
        query = { test = '"val1","val2"' },
    })
    T.ok(not ok, "should fail")
end)

T.done()
