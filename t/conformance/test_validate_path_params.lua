#!/usr/bin/env resty
--- Conformance test ported from lua-resty-openapi-validate: path_params.t
-- Validates path parameters with type and range constraints.
dofile("t/lib/test_bootstrap.lua")

local T = require("test_helper")
local ov = require("resty.openapi_validator")

local function read_file(path)
    local f = io.open(path, "r")
    assert(f, "cannot open " .. path)
    local data = f:read("*a")
    f:close()
    return data
end

local spec_str = read_file("t/specs/path_params.json")
local validator, compile_err = ov.compile(spec_str)
assert(validator, "compile failed: " .. tostring(compile_err))

-- TEST 1: valid path param
T.describe("path_params: valid userId 420", function()
    local ok, err = validator:validate_request({
        method = "GET",
        path = "/users/420",
    })
    T.ok(ok, "valid path param passes: " .. tostring(err))
end)

-- TEST 2: path param exceeds maximum (4200 > 1000)
T.describe("path_params: userId exceeds maximum", function()
    local ok, err = validator:validate_request({
        method = "GET",
        path = "/users/4200",
    })
    T.ok(not ok, "exceeding maximum fails")
    T.like(err, "userId", "error mentions userId")
end)

-- TEST 3: wrong type (string instead of integer)
T.describe("path_params: wrong type for userId", function()
    local ok, err = validator:validate_request({
        method = "GET",
        path = "/users/wrong_path_param",
    })
    T.ok(not ok, "string for integer param fails")
    T.like(err, "userId", "error mentions userId")
end)

-- TEST 4: skip path params validation
T.describe("path_params: skip path params", function()
    local ok, err = validator:validate_request({
        method = "GET",
        path = "/users/this-is-wrong-but-it-should-pass",
    }, { path = true })
    T.ok(ok, "skip path params passes: " .. tostring(err))
end)

T.done()
