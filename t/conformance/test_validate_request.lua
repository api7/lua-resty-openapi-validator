#!/usr/bin/env resty
--- Conformance test ported from kin-openapi validate_request_test.go
-- Tests: TestValidateRequest, TestValidateRequestExcludeQueryParams, TestValidateQueryParams (deepObject)
dofile("t/lib/test_bootstrap.lua")

local T = require("test_helper")
local cjson = require("cjson.safe")
local ov = require("resty.openapi_validator")

-- === TestValidateRequest ===
-- Spec with /category POST, required query param + required JSON body
local category_spec = cjson.encode({
    openapi = "3.0.0",
    info = { title = "Validator", version = "0.0.1" },
    paths = {
        ["/category"] = {
            post = {
                parameters = {
                    { name = "category", ["in"] = "query",
                      schema = { type = "string" }, required = true },
                },
                requestBody = {
                    required = true,
                    content = {
                        ["application/json"] = {
                            schema = {
                                type = "object",
                                required = { "subCategory" },
                                properties = {
                                    subCategory = { type = "string" },
                                    category = { type = "string" },
                                },
                            },
                        },
                    },
                },
                responses = { ["201"] = { description = "Created" } },
            },
        },
    },
})

local v_cat = ov.compile(category_spec)
assert(v_cat, "compile failed")

T.describe("validate_request: valid with all fields", function()
    local ok, err = v_cat:validate_request({
        method = "POST",
        path = "/category",
        query = { category = "cookies" },
        body = '{"subCategory":"Chocolate","category":"Food"}',
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("validate_request: valid without optional body field", function()
    local ok, err = v_cat:validate_request({
        method = "POST",
        path = "/category",
        query = { category = "cookies" },
        body = '{"subCategory":"Chocolate"}',
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("validate_request: invalid - missing required query param", function()
    local ok, err = v_cat:validate_request({
        method = "POST",
        path = "/category",
        query = { invalidCategory = "badCookie" },
        body = '{"subCategory":"Chocolate"}',
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    })
    T.ok(not ok, "should fail - missing required query param 'category'")
end)

T.describe("validate_request: invalid - missing required body", function()
    local ok, err = v_cat:validate_request({
        method = "POST",
        path = "/category",
        query = { category = "cookies" },
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    })
    T.ok(not ok, "should fail - required body is missing")
end)

-- === TestValidateRequestExcludeQueryParams ===
local exclude_spec = cjson.encode({
    openapi = "3.0.0",
    info = { title = "Validator", version = "0.0.1" },
    paths = {
        ["/category"] = {
            post = {
                parameters = {
                    { name = "category", ["in"] = "query",
                      schema = { type = "integer" }, required = true },
                },
                responses = { ["200"] = { description = "Ok" } },
            },
        },
    },
})

local v_exclude = ov.compile(exclude_spec)
assert(v_exclude, "compile failed")

T.describe("validate_request: exclude query params - skip query validation", function()
    local ok, err = v_exclude:validate_request({
        method = "POST",
        path = "/category",
        query = { category = "foo" }, -- string instead of integer
    }, { query = true }) -- skip query validation
    T.ok(ok, "should pass when query validation skipped: " .. tostring(err))
end)

T.describe("validate_request: exclude query params - with query validation", function()
    local ok, err = v_exclude:validate_request({
        method = "POST",
        path = "/category",
        query = { category = "foo" }, -- string instead of integer
    })
    T.ok(not ok, "should fail - 'foo' is not a valid integer")
end)

-- === TestValidateQueryParams (deepObject) ===
-- Test basic deepObject parsing and validation

-- Simple deepObject: param[key]=value
local deep_simple_spec = cjson.encode({
    openapi = "3.0.0",
    info = { title = "MyAPI", version = "0.1" },
    paths = {
        ["/test"] = {
            get = {
                operationId = "test",
                parameters = {
                    {
                        name = "param",
                        ["in"] = "query",
                        style = "deepObject",
                        explode = true,
                        schema = {
                            type = "object",
                            properties = {
                                obj = {
                                    type = "object",
                                    properties = {
                                        nestedObjOne = { type = "string" },
                                        nestedObjTwo = { type = "string" },
                                    },
                                },
                            },
                        },
                    },
                },
                responses = { ["200"] = { description = "OK" } },
            },
        },
    },
})

local v_deep = ov.compile(deep_simple_spec)
assert(v_deep, "compile failed")

T.describe("deepObject: extraneous param ignored", function()
    local ok, err = v_deep:validate_request({
        method = "GET",
        path = "/test",
        query = { anotherparam = "bar" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

-- deepObject with anyOf/allOf/oneOf
local deep_anyof_spec = cjson.encode({
    openapi = "3.0.0",
    info = { title = "MyAPI", version = "0.1" },
    paths = {
        ["/test"] = {
            get = {
                operationId = "test",
                parameters = {
                    {
                        name = "param",
                        ["in"] = "query",
                        style = "deepObject",
                        explode = true,
                        schema = {
                            type = "object",
                            properties = {
                                obj = {
                                    anyOf = {
                                        { type = "integer" },
                                        { type = "string" },
                                    },
                                },
                            },
                        },
                    },
                },
                responses = { ["200"] = { description = "OK" } },
            },
        },
    },
})

local v_deep_anyof = ov.compile(deep_anyof_spec)
assert(v_deep_anyof, "compile failed")

T.describe("deepObject: anyOf integer value (valid)", function()
    local ok, err = v_deep_anyof:validate_request({
        method = "GET",
        path = "/test",
        query = { ["param[obj]"] = "1" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

-- deepObject with allOf
local deep_allof_spec = cjson.encode({
    openapi = "3.0.0",
    info = { title = "MyAPI", version = "0.1" },
    paths = {
        ["/test"] = {
            get = {
                operationId = "test",
                parameters = {
                    {
                        name = "param",
                        ["in"] = "query",
                        style = "deepObject",
                        explode = true,
                        schema = {
                            type = "object",
                            properties = {
                                obj = {
                                    allOf = {
                                        { type = "integer" },
                                        { type = "number" },
                                    },
                                },
                            },
                        },
                    },
                },
                responses = { ["200"] = { description = "OK" } },
            },
        },
    },
})

local v_deep_allof = ov.compile(deep_allof_spec)
assert(v_deep_allof, "compile failed")

T.describe("deepObject: allOf integer value (valid)", function()
    local ok, err = v_deep_allof:validate_request({
        method = "GET",
        path = "/test",
        query = { ["param[obj]"] = "1" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

-- deepObject with oneOf (boolean)
local deep_oneof_spec = cjson.encode({
    openapi = "3.0.0",
    info = { title = "MyAPI", version = "0.1" },
    paths = {
        ["/test"] = {
            get = {
                operationId = "test",
                parameters = {
                    {
                        name = "param",
                        ["in"] = "query",
                        style = "deepObject",
                        explode = true,
                        schema = {
                            type = "object",
                            properties = {
                                obj = {
                                    oneOf = {
                                        { type = "boolean" },
                                        { type = "string" },
                                    },
                                },
                            },
                        },
                    },
                },
                responses = { ["200"] = { description = "OK" } },
            },
        },
    },
})

local v_deep_oneof = ov.compile(deep_oneof_spec)
assert(v_deep_oneof, "compile failed")

T.describe("deepObject: oneOf boolean value (valid)", function()
    local ok, err = v_deep_oneof:validate_request({
        method = "GET",
        path = "/test",
        query = { ["param[obj]"] = "true" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.done()
