#!/usr/bin/env resty
--- Tests for body.lua (requires jsonschema)
dofile("t/lib/test_bootstrap.lua")

local T = require("test_helper")
local cjson = require("cjson.safe")
local body_mod = require("resty.openapi_validator.body")

-- Helper: create a minimal route with body schema
local function make_route(schema, required)
    return {
        body_schema = schema,
        body_required = required or false,
    }
end

-- Test: required body missing
T.describe("body: required body missing", function()
    local route = make_route({ type = "object" }, true)

    local ok, errs = body_mod.validate(route, nil, "application/json")
    T.ok(not ok, "missing required body fails")
    T.like(errs[1].message, "required", "error says required")
end)

-- Test: required body empty string
T.describe("body: required body empty", function()
    local route = make_route({ type = "object" }, true)

    local ok, errs = body_mod.validate(route, "", "application/json")
    T.ok(not ok, "empty required body fails")
end)

-- Test: optional body missing is OK
T.describe("body: optional body missing", function()
    local route = make_route({ type = "object" }, false)

    local ok, errs = body_mod.validate(route, nil, "application/json")
    T.ok(ok, "optional missing body passes")
end)

-- Test: valid JSON body
T.describe("body: valid JSON body", function()
    local route = make_route({
        type = "object",
        properties = {
            name = { type = "string", minLength = 1 },
            age = { type = "integer", minimum = 0 },
        },
        required = { "name" },
    }, true)

    local body = cjson.encode({ name = "Alice", age = 30 })
    local ok, errs = body_mod.validate(route, body, "application/json")
    T.ok(ok, "valid JSON body passes")
end)

-- Test: invalid JSON body (missing required field)
T.describe("body: missing required field", function()
    local route = make_route({
        type = "object",
        properties = {
            name = { type = "string", minLength = 1 },
        },
        required = { "name" },
    }, true)

    local body = cjson.encode({ age = 30 })
    local ok, errs = body_mod.validate(route, body, "application/json")
    T.ok(not ok, "missing required field fails")
    T.is(#errs, 1, "one error")
end)

-- Test: invalid JSON body (wrong type)
T.describe("body: wrong field type", function()
    local route = make_route({
        type = "object",
        properties = {
            age = { type = "integer" },
        },
    }, true)

    local body = cjson.encode({ age = "not a number" })
    local ok, errs = body_mod.validate(route, body, "application/json")
    T.ok(not ok, "wrong type fails")
end)

-- Test: malformed JSON body
T.describe("body: malformed JSON", function()
    local route = make_route({ type = "object" }, true)

    local ok, errs = body_mod.validate(route, "{bad json", "application/json")
    T.ok(not ok, "malformed JSON fails")
    T.like(errs[1].message, "invalid JSON", "error mentions invalid JSON")
end)

-- Test: JSON content-type variations
T.describe("body: application/json charset", function()
    local route = make_route({
        type = "object",
        properties = { name = { type = "string" } },
    }, true)

    local body = cjson.encode({ name = "test" })
    local ok = body_mod.validate(route, body, "application/json; charset=utf-8")
    T.ok(ok, "JSON with charset passes")
end)

-- Test: +json content type (e.g. application/vnd.api+json)
T.describe("body: +json content type", function()
    local route = make_route({
        type = "object",
        properties = { data = { type = "string" } },
    }, true)

    local body = cjson.encode({ data = "hello" })
    local ok = body_mod.validate(route, body, "application/vnd.api+json")
    T.ok(ok, "+json content type treated as JSON")
end)

-- Test: non-JSON content type skipped
T.describe("body: non-JSON skipped", function()
    local route = make_route({ type = "object" }, true)

    local ok = body_mod.validate(route, "some xml data", "application/xml")
    T.ok(ok, "non-JSON content type skipped")
end)

-- Test: no body schema → always pass
T.describe("body: no schema", function()
    local route = { body_schema = nil, body_required = false }

    local ok = body_mod.validate(route, '{"anything": true}', "application/json")
    T.ok(ok, "no schema always passes")
end)

-- Test: nested object validation
T.describe("body: nested object", function()
    local route = make_route({
        type = "object",
        properties = {
            address = {
                type = "object",
                properties = {
                    street = { type = "string" },
                    zip = { type = "string", pattern = "^[0-9]{5}$" },
                },
                required = { "street" },
            },
        },
    }, true)

    local body = cjson.encode({ address = { street = "123 Main St", zip = "12345" } })
    local ok = body_mod.validate(route, body, "application/json")
    T.ok(ok, "valid nested object passes")

    body = cjson.encode({ address = { zip = "12345" } })
    ok = body_mod.validate(route, body, "application/json")
    T.ok(not ok, "nested missing required field fails")
end)

-- Test: array body
T.describe("body: array body", function()
    local route = make_route({
        type = "array",
        items = { type = "integer" },
    }, true)

    local body = cjson.encode({ 1, 2, 3 })
    local ok = body_mod.validate(route, body, "application/json")
    T.ok(ok, "valid array body passes")

    body = cjson.encode({ 1, "two", 3 })
    ok = body_mod.validate(route, body, "application/json")
    T.ok(not ok, "invalid array element fails")
end)

T.done()
