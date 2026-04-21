#!/usr/bin/env resty
--- Conformance test ported from kin-openapi issue707_test.go
-- Tests path parameter edge cases: type coercion, multiple params,
-- and min/max constraints.
dofile("t/lib/test_bootstrap.lua")

local T = require("test_helper")
local cjson = require("cjson.safe")
local ov = require("resty.openapi_validator")

local spec = cjson.encode({
    openapi = "3.0.0",
    info = { title = "Sample API", version = "1.0.0" },
    paths = {
        ["/items/{itemId}"] = {
            get = {
                parameters = {
                    { name = "itemId", ["in"] = "path", required = true,
                      schema = { type = "string" } },
                },
                responses = { ["200"] = { description = "OK" } },
            },
        },
        ["/orders/{orderId}"] = {
            get = {
                parameters = {
                    { name = "orderId", ["in"] = "path", required = true,
                      schema = { type = "integer" } },
                },
                responses = { ["200"] = { description = "OK" } },
            },
        },
        ["/bounded/{val}"] = {
            get = {
                parameters = {
                    { name = "val", ["in"] = "path", required = true,
                      schema = { type = "integer", minimum = 1, maximum = 100 } },
                },
                responses = { ["200"] = { description = "OK" } },
            },
        },
        ["/multi/{region}/{id}"] = {
            get = {
                parameters = {
                    { name = "region", ["in"] = "path", required = true,
                      schema = { type = "string" } },
                    { name = "id", ["in"] = "path", required = true,
                      schema = { type = "integer" } },
                },
                responses = { ["200"] = { description = "OK" } },
            },
        },
    },
})

local v = ov.compile(spec)
assert(v, "compile failed")

-- String path param accepts anything
T.describe("issue707: string path param with numeric-looking value (valid)", function()
    local ok, err = v:validate_request({
        method = "GET",
        path = "/items/42",
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue707: string path param with alpha value (valid)", function()
    local ok, err = v:validate_request({
        method = "GET",
        path = "/items/hello-world",
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

-- Integer path param rejects non-integer
T.describe("issue707: integer path param with valid integer (valid)", function()
    local ok, err = v:validate_request({
        method = "GET",
        path = "/orders/999",
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue707: integer path param with non-integer (fail)", function()
    local ok, err = v:validate_request({
        method = "GET",
        path = "/orders/not-a-number",
    })
    T.ok(not ok, "should fail - 'not-a-number' is not an integer")
end)

-- Bounded integer path param
T.describe("issue707: bounded path param within range (valid)", function()
    local ok, err = v:validate_request({
        method = "GET",
        path = "/bounded/50",
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue707: bounded path param at minimum (valid)", function()
    local ok, err = v:validate_request({
        method = "GET",
        path = "/bounded/1",
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue707: bounded path param below minimum (fail)", function()
    local ok, err = v:validate_request({
        method = "GET",
        path = "/bounded/0",
    })
    T.ok(not ok, "should fail - 0 is below minimum 1")
end)

T.describe("issue707: bounded path param above maximum (fail)", function()
    local ok, err = v:validate_request({
        method = "GET",
        path = "/bounded/101",
    })
    T.ok(not ok, "should fail - 101 is above maximum 100")
end)

-- Multiple path params
T.describe("issue707: multiple path params both valid (valid)", function()
    local ok, err = v:validate_request({
        method = "GET",
        path = "/multi/us-east/42",
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue707: multiple path params, integer param invalid (fail)", function()
    local ok, err = v:validate_request({
        method = "GET",
        path = "/multi/eu-west/abc",
    })
    T.ok(not ok, "should fail - 'abc' is not a valid integer for id param")
end)

T.done()
