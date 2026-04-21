#!/usr/bin/env luajit
--- Integration test for the compile entry point
package.path = "lib/?.lua;lib/?/init.lua;t/lib/?.lua;;" .. package.path

local T = require("test_helper")

local function read_file(path)
    local f = io.open(path, "r")
    assert(f, "cannot open " .. path)
    local data = f:read("*a")
    f:close()
    return data
end

local ov = require("resty.openapi_validator")

-- Test: compile 3.0 spec
T.describe("compile: 3.0 basic spec", function()
    local spec_str = read_file("t/specs/basic_30.json")
    local ctx, err = ov.compile(spec_str)
    T.ok(ctx ~= nil, "compile succeeds")
    T.ok(err == nil, "no error: " .. tostring(err))
    T.is(ctx.version, "3.0", "version is 3.0")
    T.ok(ctx.spec ~= nil, "spec present in context")
end)

-- Test: compile 3.1 spec (lenient)
T.describe("compile: 3.1 basic spec lenient", function()
    local spec_str = read_file("t/specs/basic_31.json")
    local ctx, err = ov.compile(spec_str, { strict = false })
    T.ok(ctx ~= nil, "compile 3.1 lenient succeeds")
    T.ok(err == nil, "no error")
    T.is(ctx.version, "3.1", "version is 3.1")
end)

-- Test: compile 3.1 with unsupported keyword (strict)
T.describe("compile: 3.1 unsupported strict", function()
    local spec_str = read_file("t/specs/unsupported_31.json")
    local ctx, err = ov.compile(spec_str, { strict = true })
    T.ok(ctx == nil, "compile fails in strict mode")
    T.like(err, "unevaluatedProperties", "error mentions keyword")
end)

-- Test: compile invalid JSON
T.describe("compile: invalid JSON", function()
    local ctx, err = ov.compile("{bad")
    T.ok(ctx == nil, "compile fails")
    T.like(err, "parse", "error mentions parse")
end)

-- Test: compile circular ref spec
T.describe("compile: circular ref", function()
    local spec_str = read_file("t/specs/circular_ref.json")
    local ctx, err = ov.compile(spec_str)
    T.ok(ctx ~= nil, "compile circular ref succeeds")
    T.ok(err == nil, "no error")
end)

-- Test: compile ref with siblings (3.1)
T.describe("compile: ref siblings 3.1", function()
    local spec_str = read_file("t/specs/ref_siblings_31.json")
    local ctx, err = ov.compile(spec_str, { strict = false })
    T.ok(ctx ~= nil, "compile succeeds")
    T.ok(err == nil, "no error")
end)

T.done()
