#!/usr/bin/env resty
--- Conformance test ported from lua-resty-openapi-validate: header.t
-- Validates header parameters with pattern constraints.
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

local spec_str = read_file("t/specs/header.json")
local validator, compile_err = ov.compile(spec_str)
assert(validator, "compile failed: " .. tostring(compile_err))

-- TEST 1: valid headers
T.describe("header: valid Authorization and Content-Type", function()
    local ok, err = validator:validate_request({
        method = "GET",
        path = "/validateHeaders",
        headers = {
            ["authorization"] = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c",
            ["content-type"] = "application/json",
        },
    })
    T.ok(ok, "valid headers pass: " .. tostring(err))
end)

-- TEST 2: missing required headers
T.describe("header: missing required headers", function()
    local ok, err = validator:validate_request({
        method = "GET",
        path = "/validateHeaders",
        headers = {
            ["no-authorization"] = "wrong",
            ["no-content-type"] = "wrong",
        },
    })
    T.ok(not ok, "missing required headers fails")
    T.like(err, "[Aa]uthorization", "error mentions Authorization")
    T.like(err, "[Cc]ontent%-[Tt]ype", "error mentions Content-Type")
end)

-- TEST 3: skip header validation
T.describe("header: skip header validation", function()
    local ok, err = validator:validate_request({
        method = "GET",
        path = "/validateHeaders",
        headers = {
            ["no-authorization"] = "wrong",
            ["no-content-type"] = "wrong",
        },
    }, { header = true })
    T.ok(ok, "skip header passes: " .. tostring(err))
end)

T.done()
