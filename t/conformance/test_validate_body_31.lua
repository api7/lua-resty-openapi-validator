#!/usr/bin/env resty
--- Conformance test ported from lua-resty-openapi-validate: body_31.t
-- Validates request body for OpenAPI 3.1 features: type arrays (nullable), const.
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

local spec_str = read_file("t/specs/body_31.json")
local validator, compile_err = ov.compile(spec_str, { strict = false })
assert(validator, "compile failed: " .. tostring(compile_err))

-- TEST 1: valid body (basic 3.1 compatibility)
T.describe("body_31: valid request body", function()
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

-- TEST 2: nullable field with null value (3.1 type array ["string", "null"])
T.describe("body_31: nullable email with null", function()
    local ok, err = validator:validate_request({
        method = "POST",
        path = "/user",
        body = cjson.encode({
            username = "alphabeta",
            email = cjson.null,
        }),
        content_type = "application/json",
    })
    T.ok(ok, "nullable email with null passes: " .. tostring(err))
end)

-- TEST 3: missing required field 'username'
T.describe("body_31: missing required username", function()
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

-- TEST 4: correct const value
T.describe("body_31: correct const value", function()
    local ok, err = validator:validate_request({
        method = "POST",
        path = "/user",
        body = cjson.encode({
            username = "alphabeta",
            role = "admin",
        }),
        content_type = "application/json",
    })
    T.ok(ok, "correct const value passes: " .. tostring(err))
end)

-- TEST 5: wrong const value
T.describe("body_31: wrong const value", function()
    local ok, err = validator:validate_request({
        method = "POST",
        path = "/user",
        body = cjson.encode({
            username = "alphabeta",
            role = "user",
        }),
        content_type = "application/json",
    })
    T.ok(not ok, "wrong const value fails")
    T.like(err, "const", "error mentions const")
end)

T.done()
