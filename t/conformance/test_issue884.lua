#!/usr/bin/env resty
--- Conformance test ported from kin-openapi issue884_test.go
-- Tests allOf with $ref to enum schema in query params (default value behavior).
-- We skip the default-value-setting aspect (SkipSettingDefaults) as our validator doesn't mutate requests.
-- Instead we test that the enum validation works with allOf $ref.
dofile("t/lib/test_bootstrap.lua")

local T = require("test_helper")
local cjson = require("cjson.safe")
local ov = require("resty.openapi_validator")

local spec = cjson.encode({
    openapi = "3.0.0",
    info = { title = "Sample API", version = "1.0.0" },
    components = {
        schemas = {
            TaskSortEnum = {
                enum = { "createdAt", "-createdAt", "updatedAt", "-updatedAt" },
            },
        },
    },
    paths = {
        ["/tasks"] = {
            get = {
                operationId = "ListTask",
                parameters = {
                    {
                        name = "withDefault",
                        ["in"] = "query",
                        schema = {
                            allOf = {
                                { ["$ref"] = "#/components/schemas/TaskSortEnum" },
                            },
                        },
                    },
                    {
                        name = "withoutDefault",
                        ["in"] = "query",
                        schema = {
                            allOf = {
                                { ["$ref"] = "#/components/schemas/TaskSortEnum" },
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

T.describe("issue884: no query params (valid - optional)", function()
    local ok, err = v:validate_request({
        method = "GET",
        path = "/tasks",
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue884: valid enum value in query (valid)", function()
    local ok, err = v:validate_request({
        method = "GET",
        path = "/tasks",
        query = { withDefault = "-createdAt" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue884: invalid enum value in query (fail)", function()
    local ok, err = v:validate_request({
        method = "GET",
        path = "/tasks",
        query = { withDefault = "invalidSort" },
    })
    T.ok(not ok, "should fail")
end)

T.done()
