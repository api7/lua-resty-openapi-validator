#!/usr/bin/env resty
--- Conformance test ported from lua-resty-openapi-validate: body.t
-- Validates request body for OpenAPI 3.0 spec.
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

local spec_str = read_file("t/specs/body.json")
local validator, compile_err = ov.compile(spec_str)
assert(validator, "compile failed: " .. tostring(compile_err))

-- TEST 1: valid body
T.describe("body: valid request body", function()
    local ok, err = validator:validate_request({
        method = "POST",
        path = "/user",
        body = cjson.encode({
            username = "alphabeta",
            email = "alphabeta@gamma.zeta",
        }),
        content_type = "application/json",
    })
    T.ok(ok, "valid body passes: " .. tostring(err))
end)

-- TEST 2: missing required field 'username'
T.describe("body: missing required field username", function()
    local ok, err = validator:validate_request({
        method = "POST",
        path = "/user",
        body = cjson.encode({
            email = "alphabeta@gamma.zeta",
        }),
        content_type = "application/json",
    })
    T.ok(not ok, "missing username fails")
    T.like(err, "username", "error mentions username")
end)

-- TEST 3: skip body validation (empty body)
T.describe("body: skip body validation", function()
    local ok, err = validator:validate_request({
        method = "POST",
        path = "/user",
        content_type = "application/json",
    }, { body = true })
    T.ok(ok, "skip body passes: " .. tostring(err))
end)

T.done()
