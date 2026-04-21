#!/usr/bin/env resty
--- Conformance tests ported from kin-openapi validate_readonly_test.go
-- Only request-relevant test cases (response validation not supported).
dofile("t/lib/test_bootstrap.lua")

local T = require("test_helper")
local cjson = require("cjson.safe")
local ov = require("resty.openapi_validator")

local function make_spec(read_write_flag)
    return cjson.encode({
        openapi = "3.0.3",
        info = { version = "1.0.0", title = "title" },
        paths = {
            ["/accounts"] = {
                post = {
                    requestBody = {
                        required = true,
                        content = {
                            ["application/json"] = {
                                schema = {
                                    type = "object",
                                    required = { "_id" },
                                    properties = {
                                        _id = {
                                            type = "string",
                                            [read_write_flag] = true,
                                        },
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
end

local req = {
    method = "POST",
    path = "/accounts",
    body = cjson.encode({ _id = "bt6kdc3d0cvp6u8u3ft0" }),
    content_type = "application/json",
}

T.describe("writeOnly in request: should pass", function()
    local v = ov.compile(make_spec("writeOnly"))
    local ok, err = v:validate_request(req)
    T.ok(ok, "writeOnly field in request should be valid: " .. tostring(err))
end)

T.describe("readOnly in request: should fail", function()
    local v = ov.compile(make_spec("readOnly"))
    local ok, err = v:validate_request(req)
    T.ok(not ok, "readOnly field in request should be invalid")
    T.like(err, "readOnly", "error should mention readOnly")
end)

T.describe("readOnly in request with skip.readOnly: should pass", function()
    local v = ov.compile(make_spec("readOnly"))
    local ok, err = v:validate_request(req, { read_only = true })
    T.ok(ok, "readOnly skipped, should pass: " .. tostring(err))
end)

T.done()
