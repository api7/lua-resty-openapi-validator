#!/usr/bin/env luajit
--- Tests for normalize.lua
package.path = "lib/?.lua;lib/?/init.lua;t/lib/?.lua;;" .. package.path

local T = require("test_helper")
local cjson = require("cjson.safe")
local normalize = require("resty.openapi_validator.normalize")

local function load_spec(filename)
    local f = io.open("t/specs/" .. filename, "r")
    assert(f, "cannot open " .. filename)
    local data = f:read("*a")
    f:close()
    return cjson.decode(data)
end

-- Test: 3.0 nullable → type array
T.describe("normalize 3.0: nullable string", function()
    local schema = { type = "string", nullable = true }
    local warnings = {}
    normalize.normalize_spec(
        { components = { schemas = { S = schema } } },
        "3.0", { strict = false }
    )
    T.ok(schema.nullable == nil, "nullable removed")
    T.ok(type(schema.type) == "table", "type became array")
    local has_null = false
    for _, t in ipairs(schema.type) do
        if t == "null" then has_null = true end
    end
    T.ok(has_null, "type array contains null")
end)

-- Test: 3.0 nullable + enum → null added to enum
T.describe("normalize 3.0: nullable enum", function()
    local schema = {
        type = "string",
        enum = { "a", "b" },
        nullable = true,
    }
    normalize.normalize_spec(
        { components = { schemas = { S = schema } } },
        "3.0", { strict = false }
    )
    T.ok(schema.nullable == nil, "nullable removed")
    -- enum should contain cjson.null
    local has_null_token = false
    for _, v in ipairs(schema.enum) do
        if v == cjson.null then has_null_token = true end
    end
    T.ok(has_null_token, "null added to enum")
end)

-- Test: 3.0 exclusiveMinimum boolean → numeric
T.describe("normalize 3.0: exclusiveMinimum bool→numeric", function()
    local schema = {
        type = "integer",
        minimum = 0,
        exclusiveMinimum = true,
    }
    normalize.normalize_spec(
        { components = { schemas = { S = schema } } },
        "3.0", { strict = false }
    )
    T.is(schema.exclusiveMinimum, 0, "exclusiveMinimum became numeric 0")
    T.ok(schema.minimum == nil, "minimum removed")
end)

-- Test: 3.0 exclusiveMaximum boolean → numeric
T.describe("normalize 3.0: exclusiveMaximum bool→numeric", function()
    local schema = {
        type = "integer",
        maximum = 100,
        exclusiveMaximum = true,
    }
    normalize.normalize_spec(
        { components = { schemas = { S = schema } } },
        "3.0", { strict = false }
    )
    T.is(schema.exclusiveMaximum, 100, "exclusiveMaximum became numeric 100")
    T.ok(schema.maximum == nil, "maximum removed")
end)

-- Test: 3.0 exclusiveMinimum: true without minimum → warning
T.describe("normalize 3.0: exclusiveMinimum without minimum", function()
    local schema = { type = "integer", exclusiveMinimum = true }
    local warnings = normalize.normalize_spec(
        { components = { schemas = { S = schema } } },
        "3.0", { strict = false }
    )
    T.ok(schema.exclusiveMinimum == nil, "exclusiveMinimum removed")
    T.ok(#warnings > 0, "warning generated")
end)

-- Test: 3.0 example field removed
T.describe("normalize 3.0: example removed", function()
    local schema = { type = "string", example = "foo" }
    normalize.normalize_spec(
        { components = { schemas = { S = schema } } },
        "3.0", { strict = false }
    )
    T.ok(schema.example == nil, "example removed")
end)

-- Test: 3.1 prefixItems → items (tuple)
T.describe("normalize 3.1: prefixItems", function()
    local schema = {
        type = "array",
        prefixItems = { { type = "string" }, { type = "integer" } },
        items = { type = "string" },
    }
    normalize.normalize_spec(
        { components = { schemas = { S = schema } } },
        "3.1", { strict = false }
    )
    T.ok(schema.prefixItems == nil, "prefixItems removed")
    T.ok(type(schema.items) == "table", "items exists")
    T.is(#schema.items, 2, "items is tuple array with 2 elements")
    T.ok(schema.additionalItems ~= nil, "additionalItems set")
    T.is(schema.additionalItems.type, "string", "additionalItems is string schema")
end)

-- Test: 3.1 $defs → definitions
T.describe("normalize 3.1: $defs → definitions", function()
    local schema = {
        type = "object",
        ["$defs"] = { Foo = { type = "string" } },
    }
    normalize.normalize_spec(
        { components = { schemas = { S = schema } } },
        "3.1", { strict = false }
    )
    T.ok(schema["$defs"] == nil, "$defs removed")
    T.ok(schema.definitions ~= nil, "definitions created")
    T.is(schema.definitions.Foo.type, "string", "Foo schema preserved")
end)

-- Test: 3.1 dependentRequired → dependencies
T.describe("normalize 3.1: dependentRequired", function()
    local schema = {
        type = "object",
        dependentRequired = { foo = { "bar", "baz" } },
    }
    normalize.normalize_spec(
        { components = { schemas = { S = schema } } },
        "3.1", { strict = false }
    )
    T.ok(schema.dependentRequired == nil, "dependentRequired removed")
    T.ok(schema.dependencies ~= nil, "dependencies created")
    T.ok(schema.dependencies.foo ~= nil, "dependencies.foo exists")
end)

-- Test: 3.1 unsupported keyword in strict mode → error
T.describe("normalize 3.1: strict unsupported keyword", function()
    local spec = load_spec("unsupported_31.json")
    local warnings, err = normalize.normalize_spec(spec, "3.1", { strict = true })
    T.ok(err ~= nil, "error returned in strict mode")
    T.like(err, "unevaluatedProperties", "error mentions the keyword")
end)

-- Test: 3.1 unsupported keyword in lenient mode → warning
T.describe("normalize 3.1: lenient unsupported keyword", function()
    local spec = load_spec("unsupported_31.json")
    local warnings, err = normalize.normalize_spec(spec, "3.1", { strict = false })
    T.ok(err == nil, "no error in lenient mode")
    T.ok(#warnings > 0, "warning generated")
end)

-- Test: full 3.0 spec compile
T.describe("normalize: full 3.0 spec", function()
    local spec = load_spec("basic_30.json")
    -- resolve refs first
    local refs = require("resty.openapi_validator.refs")
    refs.resolve(spec)

    local warnings, err = normalize.normalize_spec(spec, "3.0", { strict = false })
    T.ok(err == nil, "no error normalizing 3.0 spec")

    -- Check the nullable email field was converted
    local user = spec.components.schemas.User
    T.ok(user.properties.email.nullable == nil, "email nullable removed")
    T.ok(type(user.properties.email.type) == "table", "email type is array")

    -- Check exclusiveMinimum on path param
    local params = spec.paths["/users/{id}"].get.parameters
    local id_param
    for _, p in ipairs(params) do
        if p.name == "id" then id_param = p end
    end
    T.is(id_param.schema.exclusiveMinimum, 0, "id exclusiveMinimum is numeric")
end)

-- Test: full 3.1 spec compile
T.describe("normalize: full 3.1 spec", function()
    local spec = load_spec("basic_31.json")
    local refs = require("resty.openapi_validator.refs")
    refs.resolve(spec)

    local warnings, err = normalize.normalize_spec(spec, "3.1", { strict = false })
    T.ok(err == nil, "no error normalizing 3.1 spec")

    local item_list = spec.components.schemas.ItemList
    T.ok(item_list.properties.tags.prefixItems == nil, "prefixItems removed")
    T.ok(item_list["$defs"] == nil, "$defs removed")
    T.ok(item_list.properties.metadata.dependentRequired == nil, "dependentRequired removed")
end)

T.done()
