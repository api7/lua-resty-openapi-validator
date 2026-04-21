#!/usr/bin/env resty
--- End-to-end integration test: compile + validate_request
dofile("t/lib/test_bootstrap.lua")

local T = require("test_helper")
local cjson = require("cjson.safe")
local ov = require("resty.openapi_validator")

local function read_file(path)
    local f = io.open(path, "r")
    assert(f, "cannot open " .. path)
    local data = f:read("*a")
    f:close()
    return data
end

-- Compile the 3.0 spec once
local spec_str = read_file("t/specs/basic_30.json")
local validator, compile_err = ov.compile(spec_str)
assert(validator, "compile failed: " .. tostring(compile_err))

-- === Valid requests ===

T.describe("e2e: valid GET with path params", function()
    local ok, err = validator:validate_request({
        method = "GET",
        path = "/users/42",
        query = { limit = "10" },
    })
    T.ok(ok, "valid GET passes")
    T.ok(err == nil, "no error: " .. tostring(err))
end)

T.describe("e2e: valid POST with JSON body", function()
    local ok, err = validator:validate_request({
        method = "POST",
        path = "/users/1",
        body = cjson.encode({ name = "Alice", email = "alice@example.com" }),
        content_type = "application/json",
    })
    T.ok(ok, "valid POST passes")
    T.ok(err == nil, "no error: " .. tostring(err))
end)

T.describe("e2e: valid POST with null email (nullable)", function()
    local ok, err = validator:validate_request({
        method = "POST",
        path = "/users/1",
        body = cjson.encode({ name = "Bob", email = cjson.null }),
        content_type = "application/json",
    })
    T.ok(ok, "nullable email with null value passes")
end)

-- === Invalid requests ===

T.describe("e2e: unknown route", function()
    local ok, err = validator:validate_request({
        method = "GET",
        path = "/unknown",
    })
    T.ok(not ok, "unknown route fails")
    T.like(err, "no matching", "error mentions no matching")
end)

T.describe("e2e: wrong method", function()
    local ok, err = validator:validate_request({
        method = "DELETE",
        path = "/users/42",
    })
    T.ok(not ok, "wrong method fails")
end)

T.describe("e2e: POST missing required body", function()
    local ok, err = validator:validate_request({
        method = "POST",
        path = "/users/1",
        content_type = "application/json",
    })
    T.ok(not ok, "missing required body fails")
    T.like(err, "required", "error mentions required")
end)

T.describe("e2e: POST invalid JSON body", function()
    local ok, err = validator:validate_request({
        method = "POST",
        path = "/users/1",
        body = "{bad json",
        content_type = "application/json",
    })
    T.ok(not ok, "invalid JSON fails")
    T.like(err, "invalid JSON", "error mentions invalid JSON")
end)

T.describe("e2e: POST missing required field in body", function()
    local ok, err = validator:validate_request({
        method = "POST",
        path = "/users/1",
        body = cjson.encode({ email = "x@y.com" }),
        content_type = "application/json",
    })
    T.ok(not ok, "missing required name field fails")
end)

T.describe("e2e: POST wrong body field type", function()
    local ok, err = validator:validate_request({
        method = "POST",
        path = "/users/1",
        body = cjson.encode({ name = 123 }),
        content_type = "application/json",
    })
    T.ok(not ok, "name as integer fails")
end)

-- === Skip options ===

T.describe("e2e: skip body validation", function()
    local ok, err = validator:validate_request({
        method = "POST",
        path = "/users/1",
        content_type = "application/json",
    }, { body = true })
    T.ok(ok, "skipping body passes even without body")
end)

-- === 3.1 spec test ===

T.describe("e2e: compile and validate 3.1 spec", function()
    local spec31 = read_file("t/specs/basic_31.json")
    local v31, err = ov.compile(spec31, { strict = false })
    T.ok(v31 ~= nil, "3.1 compile succeeds")

    local ok, err = v31:validate_request({
        method = "POST",
        path = "/items",
        body = cjson.encode({ tags = { "a", 1 }, metadata = cjson.null }),
        content_type = "application/json",
    })
    T.ok(ok, "valid 3.1 POST passes: " .. tostring(err))
end)

-- === Multiple errors ===

T.describe("e2e: multiple validation errors", function()
    local spec_multi = cjson.encode({
        openapi = "3.0.0",
        info = { title = "T", version = "1" },
        paths = {
            ["/test"] = {
                post = {
                    parameters = {
                        { name = "x", ["in"] = "query", required = true,
                          schema = { type = "integer" } },
                    },
                    requestBody = {
                        required = true,
                        content = {
                            ["application/json"] = {
                                schema = {
                                    type = "object",
                                    properties = { a = { type = "string" } },
                                    required = { "a" },
                                },
                            },
                        },
                    },
                    responses = { ["200"] = { description = "OK" } },
                },
            },
        },
    })
    local v, err = ov.compile(spec_multi)
    T.ok(v ~= nil, "compile multi-error spec: " .. tostring(err))

    local ok, err = v:validate_request({
        method = "POST",
        path = "/test",
        -- missing required query param 'x'
        -- missing required body
        content_type = "application/json",
    })
    T.ok(not ok, "multiple errors detected")
    T.like(err, "required", "error mentions required")
end)

T.done()
