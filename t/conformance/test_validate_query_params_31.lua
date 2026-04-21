#!/usr/bin/env resty
--- Conformance test ported from lua-resty-openapi-validate: query_params_31.t
-- Validates OpenAPI 3.1 query params with numeric exclusiveMinimum/Maximum.
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

local spec_str = read_file("t/specs/query_params_31.json")
local validator, compile_err = ov.compile(spec_str, { strict = false })
assert(validator, "compile failed: " .. tostring(compile_err))

-- TEST 1: valid query params
T.describe("query_params_31: valid page=1 limit=10", function()
    local ok, err = validator:validate_request({
        method = "GET",
        path = "/users",
        query = { page = "1", limit = "10" },
    })
    T.ok(ok, "valid query params pass: " .. tostring(err))
end)

-- TEST 2: page=0 equals exclusiveMinimum boundary
T.describe("query_params_31: page=0 at exclusiveMinimum boundary", function()
    local ok, err = validator:validate_request({
        method = "GET",
        path = "/users",
        query = { page = "0", limit = "10" },
    })
    T.ok(not ok, "page=0 at exclusiveMinimum fails")
    T.like(err, "page", "error mentions page")
end)

-- TEST 3: limit=101 equals exclusiveMaximum boundary
T.describe("query_params_31: limit=101 at exclusiveMaximum boundary", function()
    local ok, err = validator:validate_request({
        method = "GET",
        path = "/users",
        query = { page = "1", limit = "101" },
    })
    T.ok(not ok, "limit=101 at exclusiveMaximum fails")
    T.like(err, "limit", "error mentions limit")
end)

-- TEST 4: missing both required query params
T.describe("query_params_31: missing required params", function()
    local ok, err = validator:validate_request({
        method = "GET",
        path = "/users",
        query = {},
    })
    T.ok(not ok, "missing required params fails")
    T.like(err, "page", "error mentions page")
    T.like(err, "limit", "error mentions limit")
end)

T.done()
