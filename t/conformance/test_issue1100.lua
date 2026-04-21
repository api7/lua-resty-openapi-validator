#!/usr/bin/env resty
--- Conformance test ported from kin-openapi issue1100_test.go (in testdata/)
-- Tests POST endpoint with no requestBody defined in spec but body sent.
dofile("t/lib/test_bootstrap.lua")

local T = require("test_helper")
local cjson = require("cjson.safe")
local ov = require("resty.openapi_validator")

local spec = cjson.encode({
    openapi = "3.0.3",
    info = { title = "sample api", version = "1.0.0" },
    paths = {
        ["/api/path"] = {
            post = {
                responses = { ["200"] = { description = "Ok" } },
            },
        },
    },
})

local v = ov.compile(spec)
assert(v, "compile failed")

T.describe("issue1100: empty body, no requestBody in spec (valid)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/api/path",
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue1100: body present but no requestBody in spec (valid - lenient)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/api/path",
        body = '{"data":"some+unexpected+data"}',
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    })
    T.ok(ok, "should pass (no schema to validate against): " .. tostring(err))
end)

T.done()
