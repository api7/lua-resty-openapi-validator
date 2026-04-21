#!/usr/bin/env resty
--- Conformance test ported from kin-openapi issue1045_test.go
-- Tests allOf with $ref body validation for both JSON and form-urlencoded.
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
                requestBody = {
                    required = true,
                    content = {
                        ["application/json"] = {
                            schema = { ["$ref"] = "#/components/schemas/PathRequest" },
                        },
                        ["application/x-www-form-urlencoded"] = {
                            schema = { ["$ref"] = "#/components/schemas/PathRequest" },
                        },
                    },
                },
                responses = { ["200"] = { description = "Ok" } },
            },
        },
    },
    components = {
        schemas = {
            Msg_Opt = {
                properties = {
                    msg = { type = "string" },
                },
            },
            Msg = {
                allOf = {
                    { ["$ref"] = "#/components/schemas/Msg_Opt" },
                    { required = { "msg" } },
                },
            },
            Name = {
                properties = {
                    name = { type = "string" },
                },
                required = { "name" },
            },
            PathRequest = {
                type = "object",
                allOf = {
                    { ["$ref"] = "#/components/schemas/Msg" },
                    { ["$ref"] = "#/components/schemas/Name" },
                },
            },
        },
    },
})

local v = ov.compile(spec)
assert(v, "compile failed")

T.describe("issue1045: JSON - both msg and name present (valid)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/api/path",
        body = '{"msg":"message","name":"some+name"}',
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue1045: JSON - missing msg (fail)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/api/path",
        body = '{"name":"some+name"}',
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    })
    T.ok(not ok, "should fail")
end)

T.describe("issue1045: form - both msg and name present (valid)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/api/path",
        body = "msg=message&name=some+name",
        content_type = "application/x-www-form-urlencoded",
        headers = { ["content-type"] = "application/x-www-form-urlencoded" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue1045: form - missing msg (fail)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/api/path",
        body = "name=some+name",
        content_type = "application/x-www-form-urlencoded",
        headers = { ["content-type"] = "application/x-www-form-urlencoded" },
    })
    T.ok(not ok, "should fail")
end)

T.done()
