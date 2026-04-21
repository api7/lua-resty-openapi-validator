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


-- Test: heavy $ref reuse must stay linear, not pathological.
-- Builds a spec where one schema is referenced N times across many paths,
-- and another schema chain is mutually recursive. Naive deep-copy + recursive
-- resolve blows up; the linear in-place resolver completes in milliseconds.
T.describe("refs: heavy reuse + cycles stay linear", function()
    local N = 200
    local spec = {
        openapi = "3.0.0",
        info = { title = "stress", version = "1.0" },
        paths = {},
        components = { schemas = {} },
    }

    -- 50 component schemas, each referencing the next (chain) and the previous
    -- (cycle), plus a shared "Common" schema.
    spec.components.schemas.Common = {
        type = "object",
        properties = { id = { type = "string" } },
    }
    for i = 1, 50 do
        spec.components.schemas["S" .. i] = {
            type = "object",
            properties = {
                common = { ["$ref"] = "#/components/schemas/Common" },
                next = { ["$ref"] = "#/components/schemas/S" .. ((i % 50) + 1) },
                prev = { ["$ref"] = "#/components/schemas/S" .. (((i - 2) % 50) + 1) },
            },
        }
    end

    -- N paths, each referencing a few schemas.
    for i = 1, N do
        spec.paths["/p" .. i] = {
            get = {
                responses = { ["200"] = {
                    description = "ok",
                    content = { ["application/json"] = {
                        schema = { ["$ref"] = "#/components/schemas/S" ..
                                              ((i % 50) + 1) },
                    } },
                } },
                requestBody = { content = { ["application/json"] = {
                    schema = { ["$ref"] = "#/components/schemas/Common" },
                } } },
            },
        }
    end

    local t0 = os.clock()
    local ok, err = refs.resolve(spec)
    local elapsed = os.clock() - t0
    T.ok(ok, "resolve succeeds: " .. tostring(err))
    T.ok(elapsed < 1.0,
         "resolve is linear (took " ..
         string.format("%.3f", elapsed) .. "s, must be < 1s)")

    -- Every path should now reuse the same Common table (sharing, not copies).
    local shared = spec.paths["/p1"].get.requestBody
                       .content["application/json"].schema
    local another = spec.paths["/p" .. N].get.requestBody
                        .content["application/json"].schema
    T.ok(rawequal(shared, another),
         "all references to the same $ref point to a single shared table")

    -- Cycle terminated: S1.next.prev should walk back to S1 (or registered).
    local s1 = spec.components.schemas.S1
    T.ok(s1.properties.next.properties ~= nil,
         "cycle resolved (next has properties)")
    T.ok(s1.properties.next.properties.prev ~= nil,
         "cycle resolved (next.prev exists)")
end)

T.done()
