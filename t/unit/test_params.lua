#!/usr/bin/env resty
--- Tests for params.lua (requires jsonschema)
dofile("t/lib/test_bootstrap.lua")

local T = require("test_helper")
local cjson = require("cjson.safe")
local params_mod = require("resty.openapi_validator.params")
local errors = require("resty.openapi_validator.errors")

-- Helper: create a minimal route with params
local function make_route(param_list, location)
    local by_loc = { path = {}, query = {}, header = {} }
    by_loc[location] = param_list
    return { params = by_loc }
end

-- Test: required path param missing
T.describe("params: required path param missing", function()
    local route = make_route({
        { name = "id", ["in"] = "path", required = true,
          schema = { type = "integer" } },
    }, "path")

    local ok, errs = params_mod.validate(route, {}, {}, {})
    T.ok(not ok, "validation fails")
    T.is(#errs, 1, "one error")
    T.like(errs[1].message, "required", "error says required")
    T.is(errs[1].param, "id", "error names the param")
end)

-- Test: path param present and valid
T.describe("params: path param valid integer", function()
    local route = make_route({
        { name = "id", ["in"] = "path", required = true,
          schema = { type = "integer", minimum = 1 } },
    }, "path")

    local ok, errs = params_mod.validate(route, { id = "42" }, {}, {})
    T.ok(ok, "validation passes for valid integer")
    T.ok(errs == nil, "no errors")
end)

-- Test: path param type coercion failure
T.describe("params: path param invalid type", function()
    local route = make_route({
        { name = "id", ["in"] = "path", required = true,
          schema = { type = "integer" } },
    }, "path")

    local ok, errs = params_mod.validate(route, { id = "abc" }, {}, {})
    T.ok(not ok, "validation fails for non-integer")
    T.is(#errs, 1, "one error")
end)

-- Test: optional query param missing is OK
T.describe("params: optional query param missing", function()
    local route = make_route({
        { name = "limit", ["in"] = "query",
          schema = { type = "integer" } },
    }, "query")

    local ok, errs = params_mod.validate(route, {}, {}, {})
    T.ok(ok, "optional missing param passes")
end)

-- Test: query param coercion boolean
T.describe("params: query param boolean coercion", function()
    local route = make_route({
        { name = "active", ["in"] = "query", required = true,
          schema = { type = "boolean" } },
    }, "query")

    local ok, errs = params_mod.validate(route, {}, { active = "true" }, {})
    T.ok(ok, "boolean 'true' coercion passes")
end)

-- Test: query param number coercion
T.describe("params: query param number coercion", function()
    local route = make_route({
        { name = "price", ["in"] = "query", required = true,
          schema = { type = "number", minimum = 0 } },
    }, "query")

    local ok, errs = params_mod.validate(route, {}, { price = "9.99" }, {})
    T.ok(ok, "number coercion passes")
end)

-- Test: query param with enum
T.describe("params: query param enum validation", function()
    local route = make_route({
        { name = "sort", ["in"] = "query", required = true,
          schema = { type = "string", enum = { "asc", "desc" } } },
    }, "query")

    local ok, errs = params_mod.validate(route, {}, { sort = "asc" }, {})
    T.ok(ok, "valid enum passes")

    ok, errs = params_mod.validate(route, {}, { sort = "random" }, {})
    T.ok(not ok, "invalid enum fails")
end)

-- Test: header param case-insensitive
T.describe("params: header case-insensitive", function()
    local route = make_route({
        { name = "X-Request-Id", ["in"] = "header", required = true,
          schema = { type = "string" } },
    }, "header")

    local ok, errs = params_mod.validate(route, {}, {},
        { ["x-request-id"] = "abc123" })
    T.ok(ok, "case-insensitive header match")
end)

-- Test: skip path params
T.describe("params: skip path validation", function()
    local route = make_route({
        { name = "id", ["in"] = "path", required = true,
          schema = { type = "integer" } },
    }, "path")

    local ok, errs = params_mod.validate(route, {}, {}, {}, { path = true })
    T.ok(ok, "skipped path validation passes even with missing required")
end)

-- Test: array query param with simple style
T.describe("params: array param simple style", function()
    local route = make_route({
        { name = "ids", ["in"] = "query", required = true,
          style = "simple",
          schema = { type = "array", items = { type = "integer" } } },
    }, "query")

    local ok, errs = params_mod.validate(route, {}, { ids = "1,2,3" }, {})
    T.ok(ok, "comma-separated array passes")
end)

-- Test: schema with minimum/maximum
T.describe("params: path param with min/max constraints", function()
    local route = make_route({
        { name = "page", ["in"] = "query", required = true,
          schema = { type = "integer", minimum = 1, maximum = 100 } },
    }, "query")

    local ok, errs = params_mod.validate(route, {}, { page = "50" }, {})
    T.ok(ok, "page=50 within range passes")

    ok, errs = params_mod.validate(route, {}, { page = "0" }, {})
    T.ok(not ok, "page=0 below minimum fails")

    ok, errs = params_mod.validate(route, {}, { page = "101" }, {})
    T.ok(not ok, "page=101 above maximum fails")
end)

-- Test: error formatting
T.describe("params: error format", function()
    local err_list = {
        errors.new("query", "limit", "must be integer"),
        errors.new("path", "id", "required parameter is missing"),
    }
    local formatted = errors.format(err_list)
    T.like(formatted, "query parameter 'limit'", "format includes query param")
    T.like(formatted, "path parameter 'id'", "format includes path param")
end)

T.done()
