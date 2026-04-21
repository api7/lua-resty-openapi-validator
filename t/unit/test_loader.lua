#!/usr/bin/env luajit
--- Tests for loader.lua
package.path = "lib/?.lua;lib/?/init.lua;t/lib/?.lua;;" .. package.path

local T = require("test_helper")
local loader = require("resty.openapi_validator.loader")

-- Test: parse valid JSON
T.describe("loader.parse", function()
    local spec, err = loader.parse('{"openapi":"3.0.0","info":{"title":"T","version":"1"}}')
    T.ok(spec ~= nil, "parse valid JSON returns table")
    T.ok(err == nil, "parse valid JSON no error")
    T.is(spec.openapi, "3.0.0", "openapi field correct")
end)

-- Test: parse invalid JSON
T.describe("loader.parse invalid", function()
    local spec, err = loader.parse("{bad json")
    T.ok(spec == nil, "parse invalid JSON returns nil")
    T.ok(err ~= nil, "parse invalid JSON returns error")
end)

-- Test: parse empty string
T.describe("loader.parse empty", function()
    local spec, err = loader.parse("")
    T.ok(spec == nil, "parse empty string returns nil")
    T.like(err, "non%-empty", "error mentions non-empty")
end)

-- Test: parse non-string
T.describe("loader.parse non-string", function()
    local spec, err = loader.parse(123)
    T.ok(spec == nil, "parse non-string returns nil")
end)

-- Test: detect version 3.0
T.describe("detect_version 3.0", function()
    local v, err = loader.detect_version({ openapi = "3.0.3" })
    T.is(v, "3.0", "detect 3.0.3 as 3.0")
    T.ok(err == nil, "no error for 3.0")
end)

-- Test: detect version 3.1
T.describe("detect_version 3.1", function()
    local v, err = loader.detect_version({ openapi = "3.1.0" })
    T.is(v, "3.1", "detect 3.1.0 as 3.1")
end)

-- Test: detect unsupported version
T.describe("detect_version unsupported", function()
    local v, err = loader.detect_version({ openapi = "2.0" })
    T.ok(v == nil, "returns nil for 2.0")
    T.like(err, "unsupported", "error for 2.0")
end)

-- Test: detect missing openapi field
T.describe("detect_version missing", function()
    local v, err = loader.detect_version({})
    T.ok(v == nil, "returns nil for missing field")
    T.like(err, "missing", "error mentions missing")
end)

T.done()
