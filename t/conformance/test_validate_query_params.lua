#!/usr/bin/env resty
--- Conformance test ported from lua-resty-openapi-validate: query_params.t
-- Validates query parameters with required, type, and range constraints.
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

local spec_str = read_file("t/specs/query_params.json")
local validator, compile_err = ov.compile(spec_str)
assert(validator, "compile failed: " .. tostring(compile_err))

-- TEST 1: valid query params
T.describe("query_params: valid page=1 limit=10", function()
    local ok, err = validator:validate_request({
        method = "GET",
        path = "/users",
        query = { page = "1", limit = "10" },
    })
    T.ok(ok, "valid query params pass: " .. tostring(err))
end)

-- TEST 2: missing required query params
T.describe("query_params: missing required params", function()
    local ok, err = validator:validate_request({
        method = "GET",
        path = "/users",
        query = { not_page = "1", unlimited = "10" },
    })
    T.ok(not ok, "missing required params fails")
    T.like(err, "page", "error mentions page")
    T.like(err, "limit", "error mentions limit")
end)

-- TEST 3: skip query params validation
T.describe("query_params: skip query params", function()
    local ok, err = validator:validate_request({
        method = "GET",
        path = "/users",
        query = { page = "1", limit = "wrong" },
    }, { query = true })
    T.ok(ok, "skip query params passes: " .. tostring(err))
end)

T.done()
