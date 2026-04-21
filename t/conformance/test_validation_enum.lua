#!/usr/bin/env resty
--- Conformance tests ported from kin-openapi validation_enum_test.go
dofile("t/lib/test_bootstrap.lua")

local T = require("test_helper")
local cjson = require("cjson.safe")
local ov = require("resty.openapi_validator")

-- === TestValidationWithIntegerEnum — PUT Request ===

local integer_enum_put_spec = cjson.encode({
    openapi = "3.0.0",
    info = { title = "test", version = "0.1.0" },
    paths = {
        ["/sample"] = {
            put = {
                requestBody = {
                    required = true,
                    content = {
                        ["application/json"] = {
                            schema = {
                                type = "object",
                                properties = {
                                    exenum = {
                                        type = "integer",
                                        enum = { 0, 1, 2, 3 },
                                        nullable = true,
                                    },
                                },
                            },
                        },
                    },
                },
                responses = { ["200"] = { description = "Ok" } },
            },
        },
    },
})

T.describe("integer enum PUT: valid integer value", function()
    local v = ov.compile(integer_enum_put_spec)
    local ok, err = v:validate_request({
        method = "PUT",
        path = "/sample",
        body = '{"exenum": 1}',
        content_type = "application/json",
    })
    T.ok(ok, "integer 1 in enum should pass: " .. tostring(err))
end)

T.describe("integer enum PUT: string instead of integer", function()
    local v = ov.compile(integer_enum_put_spec)
    local ok, err = v:validate_request({
        method = "PUT",
        path = "/sample",
        body = '{"exenum": "1"}',
        content_type = "application/json",
    })
    T.ok(not ok, "string '1' should fail for integer enum")
    T.ok(err and #err > 0, "should have error message")
end)

T.describe("integer enum PUT: null value (nullable)", function()
    local v = ov.compile(integer_enum_put_spec)
    local ok, err = v:validate_request({
        method = "PUT",
        path = "/sample",
        body = '{"exenum": null}',
        content_type = "application/json",
    })
    T.ok(ok, "null should pass for nullable enum: " .. tostring(err))
end)

T.describe("integer enum PUT: empty object (optional field)", function()
    local v = ov.compile(integer_enum_put_spec)
    local ok, err = v:validate_request({
        method = "PUT",
        path = "/sample",
        body = "{}",
        content_type = "application/json",
    })
    T.ok(ok, "empty object should pass (field is optional): " .. tostring(err))
end)

-- === TestValidationWithIntegerEnum — GET Request ===

local integer_enum_get_spec = cjson.encode({
    openapi = "3.0.0",
    info = { title = "test", version = "0.1.0" },
    paths = {
        ["/sample"] = {
            get = {
                parameters = {
                    {
                        name = "exenum",
                        ["in"] = "query",
                        schema = {
                            type = "integer",
                            enum = { 0, 1, 2, 3 },
                        },
                    },
                },
                responses = { ["200"] = { description = "Ok" } },
            },
        },
    },
})

T.describe("integer enum GET: valid query param", function()
    local v = ov.compile(integer_enum_get_spec)
    local ok, err = v:validate_request({
        method = "GET",
        path = "/sample",
        query = { exenum = "1" },
    })
    T.ok(ok, "exenum=1 should pass: " .. tostring(err))
end)

T.describe("integer enum GET: value not in enum", function()
    local v = ov.compile(integer_enum_get_spec)
    local ok, err = v:validate_request({
        method = "GET",
        path = "/sample",
        query = { exenum = "4" },
    })
    T.ok(not ok, "exenum=4 should fail (not in enum)")
    T.ok(err and #err > 0, "should have error message")
end)

-- === TestValidationWithStringEnum — PUT Request ===

local string_enum_put_spec = cjson.encode({
    openapi = "3.0.0",
    info = { title = "test", version = "0.1.0" },
    paths = {
        ["/sample"] = {
            put = {
                requestBody = {
                    required = true,
                    content = {
                        ["application/json"] = {
                            schema = {
                                type = "object",
                                properties = {
                                    exenum = {
                                        type = "string",
                                        enum = { "0", "1", "2", "3" },
                                    },
                                },
                            },
                        },
                    },
                },
                responses = { ["200"] = { description = "Ok" } },
            },
        },
    },
})

T.describe("string enum PUT: valid string value", function()
    local v = ov.compile(string_enum_put_spec)
    local ok, err = v:validate_request({
        method = "PUT",
        path = "/sample",
        body = '{"exenum": "1"}',
        content_type = "application/json",
    })
    T.ok(ok, "string '1' in enum should pass: " .. tostring(err))
end)

T.describe("string enum PUT: integer instead of string", function()
    local v = ov.compile(string_enum_put_spec)
    local ok, err = v:validate_request({
        method = "PUT",
        path = "/sample",
        body = '{"exenum": 1}',
        content_type = "application/json",
    })
    T.ok(not ok, "integer 1 should fail for string enum")
    T.ok(err and #err > 0, "should have error message")
end)

T.describe("string enum PUT: null value (not nullable)", function()
    local v = ov.compile(string_enum_put_spec)
    local ok, err = v:validate_request({
        method = "PUT",
        path = "/sample",
        body = '{"exenum": null}',
        content_type = "application/json",
    })
    T.ok(not ok, "null should fail for non-nullable enum")
    T.ok(err and #err > 0, "should have error message")
end)

T.describe("string enum PUT: empty object (optional field)", function()
    local v = ov.compile(string_enum_put_spec)
    local ok, err = v:validate_request({
        method = "PUT",
        path = "/sample",
        body = "{}",
        content_type = "application/json",
    })
    T.ok(ok, "empty object should pass (field is optional): " .. tostring(err))
end)

T.done()
