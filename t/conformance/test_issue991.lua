#!/usr/bin/env resty
--- Conformance test ported from kin-openapi issue991_test.go (TestValidateRequestDefault)
-- Tests array query params with enum items, explode true/false.
-- We skip the default-value-injection aspect and focus on validation.
dofile("t/lib/test_bootstrap.lua")

local T = require("test_helper")
local cjson = require("cjson.safe")
local ov = require("resty.openapi_validator")

-- explode=false version
local spec_no_explode = cjson.encode({
    openapi = "3.0.0",
    info = { title = "Validator", version = "0.0.1" },
    paths = {
        ["/category"] = {
            get = {
                parameters = {
                    {
                        ["$ref"] = "#/components/parameters/Type",
                    },
                },
                responses = { ["200"] = { description = "Ok" } },
            },
        },
    },
    components = {
        parameters = {
            Type = {
                ["in"] = "query",
                name = "type",
                required = false,
                explode = false,
                schema = {
                    type = "array",
                    items = {
                        type = "string",
                        enum = { "A", "B", "C" },
                    },
                },
            },
        },
    },
})

-- explode=true version
local spec_explode = cjson.encode({
    openapi = "3.0.0",
    info = { title = "Validator", version = "0.0.1" },
    paths = {
        ["/category"] = {
            get = {
                parameters = {
                    {
                        ["$ref"] = "#/components/parameters/Type",
                    },
                },
                responses = { ["200"] = { description = "Ok" } },
            },
        },
    },
    components = {
        parameters = {
            Type = {
                ["in"] = "query",
                name = "type",
                required = false,
                explode = true,
                schema = {
                    type = "array",
                    items = {
                        type = "string",
                        enum = { "A", "B", "C" },
                    },
                },
            },
        },
    },
})

local v_no_explode = ov.compile(spec_no_explode)
local v_explode = ov.compile(spec_explode)
assert(v_no_explode and v_explode, "compile failed")

T.describe("issue991: no query param, explode=false (valid - optional)", function()
    local ok, err = v_no_explode:validate_request({
        method = "GET",
        path = "/category",
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue991: single valid enum, explode=false (valid)", function()
    local ok, err = v_no_explode:validate_request({
        method = "GET",
        path = "/category",
        query = { type = "A" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue991: invalid enum value, explode=false (fail)", function()
    local ok, err = v_no_explode:validate_request({
        method = "GET",
        path = "/category",
        query = { type = "X" },
    })
    T.ok(not ok, "should fail")
end)

T.describe("issue991: two valid enums comma-separated, explode=false (valid)", function()
    local ok, err = v_no_explode:validate_request({
        method = "GET",
        path = "/category",
        query = { type = "A,C" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue991: single valid enum, explode=true (valid)", function()
    local ok, err = v_explode:validate_request({
        method = "GET",
        path = "/category",
        query = { type = "A" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue991: multiple valid enums, explode=true (valid)", function()
    -- explode=true means multiple query params: type=A&type=B&type=C
    -- OpenResty passes them as a table
    local ok, err = v_explode:validate_request({
        method = "GET",
        path = "/category",
        query = { type = { "A", "B", "C" } },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.done()
