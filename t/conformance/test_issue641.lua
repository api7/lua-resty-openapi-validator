#!/usr/bin/env resty
--- Conformance test ported from kin-openapi issue641_test.go
-- Tests string query params with anyOf/allOf pattern constraints.
dofile("t/lib/test_bootstrap.lua")

local T = require("test_helper")
local cjson = require("cjson.safe")
local ov = require("resty.openapi_validator")

-- anyOf: string with two patterns (1-4 digits)
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
                            type = "string",
                            anyOf = {
                                { pattern = "^[0-9]{1,4}$" },
                                { pattern = "^[0-9]{1,4}$" },
                            },
                        },
                    },
                },
                responses = { ["200"] = { description = "OK" } },
            },
        },
    },
})

-- allOf: same but with allOf
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
                            type = "string",
                            allOf = {
                                { pattern = "^[0-9]{1,4}$" },
                                { pattern = "^[0-9]{1,4}$" },
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
assert(v_anyof and v_allof, "compile failed")

T.describe("issue641: anyOf pattern - 51 (valid)", function()
    local ok, err = v_anyof:validate_request({
        method = "GET",
        path = "/items",
        query = { test = "51" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue641: anyOf pattern - 999999 (fail)", function()
    local ok, err = v_anyof:validate_request({
        method = "GET",
        path = "/items",
        query = { test = "999999" },
    })
    T.ok(not ok, "should fail")
end)

T.describe("issue641: allOf pattern - 51 (valid)", function()
    local ok, err = v_allof:validate_request({
        method = "GET",
        path = "/items",
        query = { test = "51" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue641: allOf pattern - 999999 (fail)", function()
    local ok, err = v_allof:validate_request({
        method = "GET",
        path = "/items",
        query = { test = "999999" },
    })
    T.ok(not ok, "should fail")
end)

T.done()
