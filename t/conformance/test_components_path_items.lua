#!/usr/bin/env resty
--- Conformance test ported from api7/kin-openapi PR#1 components_path_items_test.go
-- Tests OAS 3.1 components/pathItems with $ref resolution.
dofile("t/lib/test_bootstrap.lua")

local T = require("test_helper")
local cjson = require("cjson.safe")
local ov = require("resty.openapi_validator")

local spec = cjson.encode({
    openapi = "3.1.0",
    info = { title = "OAS 3.1 Gap Tests", version = "1.0.0" },
    paths = {
        ["/widget"] = {
            ["$ref"] = "#/components/pathItems/WidgetPath",
        },
    },
    components = {
        pathItems = {
            WidgetPath = {
                post = {
                    operationId = "createWidget",
                    requestBody = {
                        required = true,
                        content = {
                            ["application/json"] = {
                                schema = { ["$ref"] = "#/components/schemas/Widget" },
                            },
                        },
                    },
                    responses = { ["200"] = { description = "ok" } },
                },
            },
        },
        schemas = {
            Widget = {
                type = "object",
                required = { "name" },
                properties = {
                    name = { type = "string" },
                },
            },
        },
    },
})

local v = ov.compile(spec)
assert(v, "compile failed")

T.describe("PR#1: components/pathItems - valid body (valid)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/widget",
        body = '{"name": "foo"}',
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("PR#1: components/pathItems - missing required 'name' (fail)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/widget",
        body = '{"notaname": "foo"}',
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    })
    T.ok(not ok, "should fail")
    T.ok(err and err:find("name", 1, true), "error should mention 'name': " .. tostring(err))
end)

T.done()
