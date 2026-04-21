#!/usr/bin/env resty
--- Conformance tests ported from kin-openapi validation_discriminator_test.go
dofile("t/lib/test_bootstrap.lua")

local T = require("test_helper")
local cjson = require("cjson.safe")
local ov = require("resty.openapi_validator")

local spec = cjson.encode({
    openapi = "3.0.0",
    info = { version = "0.2.0", title = "yaAPI" },
    paths = {
        ["/blob"] = {
            put = {
                operationId = "SetObj",
                requestBody = {
                    required = true,
                    content = {
                        ["application/json"] = {
                            schema = { ["$ref"] = "#/components/schemas/blob" },
                        },
                    },
                },
                responses = { ["200"] = { description = "Ok" } },
            },
        },
    },
    components = {
        schemas = {
            blob = {
                oneOf = {
                    { ["$ref"] = "#/components/schemas/objA" },
                    { ["$ref"] = "#/components/schemas/objB" },
                },
                discriminator = {
                    propertyName = "discr",
                    mapping = {
                        objA = "#/components/schemas/objA",
                        objB = "#/components/schemas/objB",
                    },
                },
            },
            genericObj = {
                type = "object",
                required = { "discr" },
                properties = {
                    discr = {
                        type = "string",
                        enum = { "objA", "objB" },
                    },
                },
            },
            objA = {
                allOf = {
                    { ["$ref"] = "#/components/schemas/genericObj" },
                    {
                        type = "object",
                        properties = {
                            base64 = { type = "string" },
                        },
                    },
                },
            },
            objB = {
                allOf = {
                    { ["$ref"] = "#/components/schemas/genericObj" },
                    {
                        type = "object",
                        properties = {
                            value = { type = "integer" },
                        },
                    },
                },
            },
        },
    },
})

-- Without explicit discriminator support, jsonschema evaluates all oneOf
-- branches. Both objA and objB match because additionalProperties is allowed
-- by default, so the body satisfies both allOf compositions. This is correct
-- jsonschema oneOf behavior — kin-openapi relies on discriminator logic to
-- pick the right branch.
T.describe("discriminator: objA body matches multiple oneOf branches (no discriminator support)", function()
    local v, err = ov.compile(spec)
    T.ok(v, "spec should compile: " .. tostring(err))

    local ok, verr = v:validate_request({
        method = "PUT",
        path = "/blob",
        body = cjson.encode({
            discr = "objA",
            base64 = "S25vY2sgS25vY2ssIE5lbyAuLi4=",
        }),
        content_type = "application/json",
    })
    T.ok(not ok, "should fail: matches both oneOf branches without discriminator")
    T.like(verr, "matches both", "error mentions matching multiple schemas")
end)

-- When schemas use additionalProperties: false + required fields, oneOf
-- branches become mutually exclusive and discriminator is not needed.
local strict_spec = cjson.encode({
    openapi = "3.0.0",
    info = { version = "0.2.0", title = "yaAPI" },
    paths = {
        ["/blob"] = {
            put = {
                operationId = "SetObj",
                requestBody = {
                    required = true,
                    content = {
                        ["application/json"] = {
                            schema = { ["$ref"] = "#/components/schemas/blob" },
                        },
                    },
                },
                responses = { ["200"] = { description = "Ok" } },
            },
        },
    },
    components = {
        schemas = {
            blob = {
                oneOf = {
                    { ["$ref"] = "#/components/schemas/objA" },
                    { ["$ref"] = "#/components/schemas/objB" },
                },
            },
            objA = {
                type = "object",
                required = { "discr", "base64" },
                properties = {
                    discr = { type = "string", enum = { "objA" } },
                    base64 = { type = "string" },
                },
                additionalProperties = false,
            },
            objB = {
                type = "object",
                required = { "discr", "value" },
                properties = {
                    discr = { type = "string", enum = { "objB" } },
                    value = { type = "integer" },
                },
                additionalProperties = false,
            },
        },
    },
})

T.describe("discriminator: objA with strict schemas (mutually exclusive oneOf)", function()
    local v, err = ov.compile(strict_spec)
    T.ok(v, "strict spec should compile: " .. tostring(err))

    local ok, verr = v:validate_request({
        method = "PUT",
        path = "/blob",
        body = cjson.encode({
            discr = "objA",
            base64 = "S25vY2sgS25vY2ssIE5lbyAuLi4=",
        }),
        content_type = "application/json",
    })
    T.ok(ok, "objA request should pass with strict schemas: " .. tostring(verr))
end)

T.done()
