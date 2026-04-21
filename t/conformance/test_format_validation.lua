#!/usr/bin/env resty
--- Conformance tests for format keyword validation.
-- Covers uuid, date, date-time, uri, email, ipv4, hostname formats.
-- Each format has positive and negative cases.
dofile("t/lib/test_bootstrap.lua")

local T = require("test_helper")
local cjson = require("cjson.safe")
local ov = require("resty.openapi_validator")


local function make_format_spec(format_name)
    return cjson.encode({
        openapi = "3.0.0",
        info = { title = "FormatTest", version = "0.1" },
        paths = {
            ["/test"] = {
                post = {
                    requestBody = {
                        required = true,
                        content = {
                            ["application/json"] = {
                                schema = {
                                    type = "object",
                                    required = { "value" },
                                    properties = {
                                        value = {
                                            type = "string",
                                            format = format_name,
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
end


local function validate_format(format_name, value)
    local spec = make_format_spec(format_name)
    local v, err = ov.compile(spec)
    assert(v, "compile failed for format '" .. format_name .. "': " .. tostring(err))
    return v:validate_request({
        method = "POST",
        path = "/test",
        body = cjson.encode({ value = value }),
        content_type = "application/json",
    })
end


-- uuid
T.describe("format uuid: valid lowercase", function()
    local ok, err = validate_format("uuid", "550e8400-e29b-41d4-a716-446655440000")
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("format uuid: valid uppercase", function()
    local ok, err = validate_format("uuid", "550E8400-E29B-41D4-A716-446655440000")
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("format uuid: invalid - missing segment", function()
    local ok = validate_format("uuid", "550e8400-e29b-41d4-a716")
    T.ok(not ok, "should fail")
end)

T.describe("format uuid: invalid - no hyphens", function()
    local ok = validate_format("uuid", "550e8400e29b41d4a716446655440000")
    T.ok(not ok, "should fail")
end)

T.describe("format uuid: invalid - random string", function()
    local ok = validate_format("uuid", "not-a-uuid")
    T.ok(not ok, "should fail")
end)


-- date
T.describe("format date: valid", function()
    local ok, err = validate_format("date", "2024-01-15")
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("format date: valid - end of month", function()
    local ok, err = validate_format("date", "2024-12-31")
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("format date: invalid - wrong separator", function()
    local ok = validate_format("date", "2024/01/15")
    T.ok(not ok, "should fail")
end)

T.describe("format date: invalid - month 13", function()
    local ok = validate_format("date", "2024-13-01")
    T.ok(not ok, "should fail")
end)

T.describe("format date: invalid - day 32", function()
    local ok = validate_format("date", "2024-01-32")
    T.ok(not ok, "should fail")
end)

T.describe("format date: invalid - incomplete", function()
    local ok = validate_format("date", "2024-01")
    T.ok(not ok, "should fail")
end)


-- date-time
T.describe("format date-time: valid UTC", function()
    local ok, err = validate_format("date-time", "2024-01-15T10:30:00Z")
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("format date-time: valid with offset", function()
    local ok, err = validate_format("date-time", "2024-01-15T10:30:00+08:00")
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("format date-time: valid with fractional seconds", function()
    local ok, err = validate_format("date-time", "2024-01-15T10:30:00.123Z")
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("format date-time: invalid - no timezone", function()
    local ok = validate_format("date-time", "2024-01-15T10:30:00")
    T.ok(not ok, "should fail")
end)

T.describe("format date-time: invalid - date only", function()
    local ok = validate_format("date-time", "2024-01-15")
    T.ok(not ok, "should fail")
end)

T.describe("format date-time: invalid - random string", function()
    local ok = validate_format("date-time", "not-a-datetime")
    T.ok(not ok, "should fail")
end)


-- uri
T.describe("format uri: valid https", function()
    local ok, err = validate_format("uri", "https://example.com/path")
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("format uri: valid mailto", function()
    local ok, err = validate_format("uri", "mailto:user@example.com")
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("format uri: valid urn", function()
    local ok, err = validate_format("uri", "urn:isbn:0451450523")
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("format uri: invalid - no scheme", function()
    local ok = validate_format("uri", "example.com/path")
    T.ok(not ok, "should fail")
end)

T.describe("format uri: invalid - just a path", function()
    local ok = validate_format("uri", "/just/a/path")
    T.ok(not ok, "should fail")
end)


-- email (already supported, but add reject test)
T.describe("format email: valid", function()
    local ok, err = validate_format("email", "user@example.com")
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("format email: invalid - no @", function()
    local ok = validate_format("email", "userexample.com")
    T.ok(not ok, "should fail")
end)

T.describe("format email: invalid - no domain", function()
    local ok = validate_format("email", "user@")
    T.ok(not ok, "should fail")
end)


-- ipv4 (already supported)
T.describe("format ipv4: valid", function()
    local ok, err = validate_format("ipv4", "192.168.1.1")
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("format ipv4: invalid - out of range", function()
    local ok = validate_format("ipv4", "256.1.1.1")
    T.ok(not ok, "should fail")
end)


-- hostname (already supported)
T.describe("format hostname: valid", function()
    local ok, err = validate_format("hostname", "example.com")
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("format hostname: invalid - has space", function()
    local ok = validate_format("hostname", "exam ple.com")
    T.ok(not ok, "should fail")
end)

T.done()
