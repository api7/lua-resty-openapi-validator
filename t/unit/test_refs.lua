#!/usr/bin/env luajit
--- Tests for refs.lua
dofile("t/lib/test_bootstrap.lua")

local T = require("test_helper")
local cjson = require("cjson.safe")
local refs = require("resty.openapi_validator.refs")

local function load_spec(filename)
    local f = io.open("t/specs/" .. filename, "r")
    assert(f, "cannot open " .. filename)
    local data = f:read("*a")
    f:close()
    return cjson.decode(data)
end

-- Test: basic $ref resolution
T.describe("refs: basic resolution", function()
    local spec = load_spec("basic_30.json")
    local ok, err = refs.resolve(spec)
    T.ok(ok, "resolve succeeds")
    T.ok(err == nil, "no error")

    -- The $ref in POST /users/{id} requestBody should be resolved
    local body_schema = spec.paths["/users/{id}"].post.requestBody
                            .content["application/json"].schema
    T.ok(body_schema.type == "object", "ref resolved to User schema type")
    T.ok(body_schema.properties ~= nil, "ref resolved has properties")
    T.ok(body_schema.properties.name ~= nil, "User has name property")
end)

-- Test: circular $ref does not error
T.describe("refs: circular ref", function()
    local spec = load_spec("circular_ref.json")
    local ok, err = refs.resolve(spec)
    T.ok(ok, "resolve circular ref succeeds")
    T.ok(err == nil, "no error for circular ref")

    -- Node schema should exist
    local node = spec.components.schemas.Node
    T.ok(node.type == "object", "Node is object")
    T.ok(node.properties.children ~= nil, "Node has children")
end)

-- Test: $ref with siblings (OAS 3.1)
T.describe("refs: $ref with siblings (3.1 allOf)", function()
    local spec = load_spec("ref_siblings_31.json")
    local ok, err = refs.resolve(spec)
    T.ok(ok, "resolve succeeds")

    local body_schema = spec.paths["/items"].post.requestBody
                            .content["application/json"].schema
    T.ok(body_schema.allOf ~= nil, "sibling ref wrapped in allOf")
    T.is(#body_schema.allOf, 2, "allOf has 2 elements")
    T.is(body_schema.allOf[1].type, "string", "first element is resolved ref")
    T.is(body_schema.allOf[2].maxLength, 10, "second element has sibling keyword")
end)

-- Test: external ref is rejected
T.describe("refs: external ref rejected", function()
    local spec = {
        openapi = "3.0.0",
        paths = {},
        components = {
            schemas = {
                Foo = {
                    ["$ref"] = "https://example.com/schemas/Bar"
                }
            }
        }
    }
    local ok, err = refs.resolve(spec)
    T.ok(not ok, "external ref rejected")
    T.like(err, "external", "error mentions external")
end)

T.done()
