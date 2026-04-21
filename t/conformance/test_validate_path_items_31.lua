#!/usr/bin/env resty
--- Conformance test ported from lua-resty-openapi-validate: path_items_31.t
-- Validates OAS 3.1 components/pathItems with $ref.
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

local spec_str = read_file("t/specs/path_items_31.json")
local validator, compile_err = ov.compile(spec_str, { strict = false })
assert(validator, "compile failed: " .. tostring(compile_err))

-- TEST 1: valid GET with userId 420
T.describe("path_items_31: valid GET /users/420", function()
    local ok, err = validator:validate_request({
        method = "GET",
        path = "/users/420",
    })
    T.ok(ok, "valid GET passes: " .. tostring(err))
end)

-- TEST 2: userId exceeds maximum (4200 > 1000)
T.describe("path_items_31: userId exceeds max", function()
    local ok, err = validator:validate_request({
        method = "GET",
        path = "/users/4200",
    })
    T.ok(not ok, "exceeding maximum fails")
    T.like(err, "userId", "error mentions userId")
end)

-- TEST 3: non-integer path param
T.describe("path_items_31: non-integer userId", function()
    local ok, err = validator:validate_request({
        method = "GET",
        path = "/users/not-an-integer",
    })
    T.ok(not ok, "non-integer fails")
    T.like(err, "userId", "error mentions userId")
end)

-- TEST 4: valid DELETE with userId 5
T.describe("path_items_31: valid DELETE /users/5", function()
    local ok, err = validator:validate_request({
        method = "DELETE",
        path = "/users/5",
    })
    T.ok(ok, "valid DELETE passes: " .. tostring(err))
end)

T.done()
