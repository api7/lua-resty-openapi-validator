#!/usr/bin/env resty
--- Conformance tests ported from kin-openapi openapi3filter
-- Tests the same scenarios as kin-openapi to ensure behavioral parity.
dofile("t/lib/test_bootstrap.lua")

local T = require("test_helper")
local cjson = require("cjson.safe")
local ov = require("resty.openapi_validator")

-- === Test 1: kin-openapi TestValidateRequest — /category POST ===
-- From: validate_request_test.go TestValidateRequest

T.describe("kin: /category POST - valid with all fields", function()
    local spec = cjson.encode({
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
    local v = ov.compile(spec)

    local ok, err = v:validate_request({
        method = "POST",
        path = "/category",
        query = { category = "cookies" },
        body = cjson.encode({ subCategory = "Chocolate", category = "Food" }),
        content_type = "application/json",
    })
    T.ok(ok, "valid request passes: " .. tostring(err))
end)

T.describe("kin: /category POST - missing required query param", function()
    local spec = cjson.encode({
        openapi = "3.0.0",
        info = { title = "V", version = "1" },
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
    local v = ov.compile(spec)

    local ok, err = v:validate_request({
        method = "POST",
        path = "/category",
        query = { invalidCategory = "badCookie" },
        body = cjson.encode({ subCategory = "Chocolate" }),
        content_type = "application/json",
    })
    T.ok(not ok, "missing required query param fails")
    T.like(err, "required", "error mentions required")
end)

T.describe("kin: /category POST - missing required body", function()
    local spec = cjson.encode({
        openapi = "3.0.0",
        info = { title = "V", version = "1" },
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
    local v = ov.compile(spec)

    local ok, err = v:validate_request({
        method = "POST",
        path = "/category",
        query = { category = "cookies" },
        content_type = "application/json",
    })
    T.ok(not ok, "missing required body fails")
end)

-- === Test 2: kin-openapi TestValidationWithIntegerEnum ===
-- From: validation_enum_test.go TestValidationWithIntegerEnum

T.describe("kin: integer enum - valid value", function()
    local spec = cjson.encode({
        openapi = "3.0.0",
        info = { title = "Enum", version = "0.1" },
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
    local v = ov.compile(spec)

    -- valid integer enum value
    local ok, err = v:validate_request({
        method = "PUT", path = "/sample",
        body = '{"exenum": 1}', content_type = "application/json",
    })
    T.ok(ok, "enum value 1 passes: " .. tostring(err))

    -- string instead of integer should fail
    ok, err = v:validate_request({
        method = "PUT", path = "/sample",
        body = '{"exenum": "1"}', content_type = "application/json",
    })
    T.ok(not ok, "string '1' for integer enum fails")

    -- null for nullable should pass
    ok, err = v:validate_request({
        method = "PUT", path = "/sample",
        body = '{"exenum": null}', content_type = "application/json",
    })
    T.ok(ok, "null for nullable enum passes: " .. tostring(err))

    -- empty object should pass (exenum not required)
    ok, err = v:validate_request({
        method = "PUT", path = "/sample",
        body = '{}', content_type = "application/json",
    })
    T.ok(ok, "empty object passes: " .. tostring(err))
end)

-- === Test 3: kin-openapi TestValidationWithStringEnum ===
-- From: validation_enum_test.go TestValidationWithStringEnum

T.describe("kin: string enum query param", function()
    local spec = cjson.encode({
        openapi = "3.0.0",
        info = { title = "Enum", version = "0.1" },
        paths = {
            ["/sample"] = {
                get = {
                    parameters = {
                        { name = "exenum", ["in"] = "query",
                          schema = { type = "integer", enum = { 0, 1, 2, 3 } } },
                    },
                    responses = { ["200"] = { description = "Ok" } },
                },
            },
        },
    })
    local v = ov.compile(spec)

    -- valid enum
    local ok, err = v:validate_request({
        method = "GET", path = "/sample", query = { exenum = "1" },
    })
    T.ok(ok, "exenum=1 passes: " .. tostring(err))

    -- invalid enum
    ok, err = v:validate_request({
        method = "GET", path = "/sample", query = { exenum = "4" },
    })
    T.ok(not ok, "exenum=4 fails (not in enum)")
end)

-- === Test 4: Path parameter validation ===
-- From: validation_test.go TestFilter

T.describe("kin: path param maxLength", function()
    local spec = cjson.encode({
        openapi = "3.0.0",
        info = { title = "API", version = "0.1" },
        paths = {
            ["/prefix/{pathArg}/suffix"] = {
                post = {
                    parameters = {
                        { name = "pathArg", ["in"] = "path", required = true,
                          schema = { type = "string", maxLength = 2 } },
                    },
                    requestBody = {
                        required = true,
                        content = {
                            ["application/json"] = {
                                schema = { type = "object" },
                            },
                        },
                    },
                    responses = { ["200"] = { description = "Ok" } },
                },
            },
        },
    })
    local v = ov.compile(spec)

    -- valid: pathArg = "ab" (2 chars, within maxLength)
    local ok, err = v:validate_request({
        method = "POST", path = "/prefix/ab/suffix",
        body = '{}', content_type = "application/json",
    })
    T.ok(ok, "pathArg=ab passes: " .. tostring(err))

    -- invalid: pathArg = "abc" (3 chars, exceeds maxLength 2)
    ok, err = v:validate_request({
        method = "POST", path = "/prefix/abc/suffix",
        body = '{}', content_type = "application/json",
    })
    T.ok(not ok, "pathArg=abc fails (exceeds maxLength)")
end)

-- === Test 5: Request body with nested objects ===
-- From: validation_test.go TestValidateRequestBody

T.describe("kin: nested required property", function()
    local spec = cjson.encode({
        openapi = "3.0.0",
        info = { title = "API", version = "1" },
        paths = {
            ["/accounts"] = {
                post = {
                    requestBody = {
                        required = true,
                        content = {
                            ["application/json"] = {
                                schema = {
                                    type = "object",
                                    required = { "name" },
                                    properties = {
                                        name = { type = "string" },
                                        settings = {
                                            type = "object",
                                            properties = {
                                                theme = { type = "string",
                                                    enum = { "light", "dark" } },
                                            },
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
    local v = ov.compile(spec)

    -- valid
    local ok, err = v:validate_request({
        method = "POST", path = "/accounts",
        body = cjson.encode({ name = "test", settings = { theme = "dark" } }),
        content_type = "application/json",
    })
    T.ok(ok, "valid nested body passes: " .. tostring(err))

    -- missing required name
    ok, err = v:validate_request({
        method = "POST", path = "/accounts",
        body = cjson.encode({ settings = { theme = "dark" } }),
        content_type = "application/json",
    })
    T.ok(not ok, "missing required name fails")

    -- invalid enum in nested
    ok, err = v:validate_request({
        method = "POST", path = "/accounts",
        body = cjson.encode({ name = "test", settings = { theme = "blue" } }),
        content_type = "application/json",
    })
    T.ok(not ok, "invalid nested enum fails")
end)

-- === Test 6: $ref resolution in request body ===

T.describe("kin: $ref in request body schema", function()
    local spec = cjson.encode({
        openapi = "3.0.0",
        info = { title = "API", version = "1" },
        paths = {
            ["/pets"] = {
                post = {
                    requestBody = {
                        required = true,
                        content = {
                            ["application/json"] = {
                                schema = { ["$ref"] = "#/components/schemas/Pet" },
                            },
                        },
                    },
                    responses = { ["200"] = { description = "Ok" } },
                },
            },
        },
        components = {
            schemas = {
                Pet = {
                    type = "object",
                    required = { "name", "species" },
                    properties = {
                        name = { type = "string", minLength = 1 },
                        species = { type = "string", enum = { "dog", "cat", "fish" } },
                        age = { type = "integer", minimum = 0 },
                    },
                },
            },
        },
    })
    local v = ov.compile(spec)

    -- valid
    local ok, err = v:validate_request({
        method = "POST", path = "/pets",
        body = cjson.encode({ name = "Buddy", species = "dog", age = 3 }),
        content_type = "application/json",
    })
    T.ok(ok, "valid pet passes: " .. tostring(err))

    -- missing required species
    ok, err = v:validate_request({
        method = "POST", path = "/pets",
        body = cjson.encode({ name = "Buddy" }),
        content_type = "application/json",
    })
    T.ok(not ok, "missing species fails")

    -- invalid species enum
    ok, err = v:validate_request({
        method = "POST", path = "/pets",
        body = cjson.encode({ name = "Buddy", species = "dragon" }),
        content_type = "application/json",
    })
    T.ok(not ok, "invalid species enum fails")

    -- negative age
    ok, err = v:validate_request({
        method = "POST", path = "/pets",
        body = cjson.encode({ name = "Buddy", species = "cat", age = -1 }),
        content_type = "application/json",
    })
    T.ok(not ok, "negative age fails")
end)

-- === Test 7: allOf/anyOf/oneOf in body ===

T.describe("kin: allOf body validation", function()
    local spec = cjson.encode({
        openapi = "3.0.0",
        info = { title = "API", version = "1" },
        paths = {
            ["/items"] = {
                post = {
                    requestBody = {
                        required = true,
                        content = {
                            ["application/json"] = {
                                schema = {
                                    allOf = {
                                        {
                                            type = "object",
                                            properties = { id = { type = "integer" } },
                                            required = { "id" },
                                        },
                                        {
                                            type = "object",
                                            properties = { name = { type = "string" } },
                                            required = { "name" },
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
    local v = ov.compile(spec)

    -- valid: satisfies both schemas
    local ok, err = v:validate_request({
        method = "POST", path = "/items",
        body = cjson.encode({ id = 1, name = "Widget" }),
        content_type = "application/json",
    })
    T.ok(ok, "allOf valid passes: " .. tostring(err))

    -- missing name (required by second schema)
    ok, err = v:validate_request({
        method = "POST", path = "/items",
        body = cjson.encode({ id = 1 }),
        content_type = "application/json",
    })
    T.ok(not ok, "allOf missing name fails")
end)

-- === Test 8: Multiple content types ===

T.describe("kin: exclude query param validation", function()
    local spec = cjson.encode({
        openapi = "3.0.0",
        info = { title = "V", version = "0.0.1" },
        paths = {
            ["/api/test"] = {
                get = {
                    parameters = {
                        { name = "num", ["in"] = "query",
                          schema = { type = "integer" }, required = true },
                    },
                    responses = { ["200"] = { description = "Ok" } },
                },
            },
        },
    })
    local v = ov.compile(spec)

    -- skip query → should pass even with missing param
    local ok, err = v:validate_request({
        method = "GET", path = "/api/test",
    }, { query = true })
    T.ok(ok, "skipping query validation passes: " .. tostring(err))

    -- without skip → should fail
    ok, err = v:validate_request({
        method = "GET", path = "/api/test",
    })
    T.ok(not ok, "without skip fails for missing required param")
end)

-- === Test 9: additionalProperties ===

T.describe("kin: additionalProperties false", function()
    local spec = cjson.encode({
        openapi = "3.0.0",
        info = { title = "API", version = "1" },
        paths = {
            ["/strict"] = {
                post = {
                    requestBody = {
                        required = true,
                        content = {
                            ["application/json"] = {
                                schema = {
                                    type = "object",
                                    properties = {
                                        name = { type = "string" },
                                    },
                                    additionalProperties = false,
                                },
                            },
                        },
                    },
                    responses = { ["200"] = { description = "Ok" } },
                },
            },
        },
    })
    local v = ov.compile(spec)

    -- valid: only known property
    local ok, err = v:validate_request({
        method = "POST", path = "/strict",
        body = cjson.encode({ name = "test" }),
        content_type = "application/json",
    })
    T.ok(ok, "valid strict body passes: " .. tostring(err))

    -- extra property should fail
    ok, err = v:validate_request({
        method = "POST", path = "/strict",
        body = cjson.encode({ name = "test", extra = "bad" }),
        content_type = "application/json",
    })
    T.ok(not ok, "additionalProperties false rejects extra field")
end)

-- === Test 10: Petstore fixture ===

T.describe("kin: petstore-style spec", function()
    local spec = cjson.encode({
        openapi = "3.0.0",
        info = { title = "Petstore", version = "1.0.0" },
        paths = {
            ["/pets"] = {
                get = {
                    parameters = {
                        { name = "limit", ["in"] = "query",
                          schema = { type = "integer", minimum = 1, maximum = 100 } },
                        { name = "status", ["in"] = "query",
                          schema = { type = "string",
                                     enum = { "available", "pending", "sold" } } },
                    },
                    responses = { ["200"] = { description = "OK" } },
                },
                post = {
                    requestBody = {
                        required = true,
                        content = {
                            ["application/json"] = {
                                schema = {
                                    type = "object",
                                    required = { "name" },
                                    properties = {
                                        name = { type = "string", minLength = 1 },
                                        tag = { type = "string" },
                                        status = { type = "string",
                                                   enum = { "available", "pending", "sold" } },
                                    },
                                },
                            },
                        },
                    },
                    responses = { ["201"] = { description = "Created" } },
                },
            },
            ["/pets/{petId}"] = {
                get = {
                    parameters = {
                        { name = "petId", ["in"] = "path", required = true,
                          schema = { type = "integer", minimum = 1 } },
                    },
                    responses = { ["200"] = { description = "OK" } },
                },
                put = {
                    parameters = {
                        { name = "petId", ["in"] = "path", required = true,
                          schema = { type = "integer", minimum = 1 } },
                    },
                    requestBody = {
                        required = true,
                        content = {
                            ["application/json"] = {
                                schema = {
                                    type = "object",
                                    properties = {
                                        name = { type = "string" },
                                        status = { type = "string",
                                                   enum = { "available", "pending", "sold" } },
                                    },
                                },
                            },
                        },
                    },
                    responses = { ["200"] = { description = "OK" } },
                },
                delete = {
                    parameters = {
                        { name = "petId", ["in"] = "path", required = true,
                          schema = { type = "integer", minimum = 1 } },
                    },
                    responses = { ["204"] = { description = "Deleted" } },
                },
            },
        },
    })

    local v = ov.compile(spec)

    -- GET /pets with valid query
    local ok, err = v:validate_request({
        method = "GET", path = "/pets",
        query = { limit = "10", status = "available" },
    })
    T.ok(ok, "GET /pets valid: " .. tostring(err))

    -- GET /pets with invalid limit
    ok, err = v:validate_request({
        method = "GET", path = "/pets",
        query = { limit = "0" },
    })
    T.ok(not ok, "GET /pets limit=0 fails")

    -- GET /pets with invalid status enum
    ok, err = v:validate_request({
        method = "GET", path = "/pets",
        query = { status = "unknown" },
    })
    T.ok(not ok, "GET /pets invalid status fails")

    -- POST /pets valid
    ok, err = v:validate_request({
        method = "POST", path = "/pets",
        body = cjson.encode({ name = "Buddy", status = "available" }),
        content_type = "application/json",
    })
    T.ok(ok, "POST /pets valid: " .. tostring(err))

    -- POST /pets missing required name
    ok, err = v:validate_request({
        method = "POST", path = "/pets",
        body = cjson.encode({ status = "available" }),
        content_type = "application/json",
    })
    T.ok(not ok, "POST /pets missing name fails")

    -- GET /pets/42
    ok, err = v:validate_request({
        method = "GET", path = "/pets/42",
    })
    T.ok(ok, "GET /pets/42 valid: " .. tostring(err))

    -- GET /pets/0 (below minimum)
    ok, err = v:validate_request({
        method = "GET", path = "/pets/0",
    })
    T.ok(not ok, "GET /pets/0 fails (minimum 1)")

    -- PUT /pets/1 valid
    ok, err = v:validate_request({
        method = "PUT", path = "/pets/1",
        body = cjson.encode({ name = "Buddy Jr", status = "sold" }),
        content_type = "application/json",
    })
    T.ok(ok, "PUT /pets/1 valid: " .. tostring(err))

    -- DELETE /pets/5
    ok, err = v:validate_request({
        method = "DELETE", path = "/pets/5",
    })
    T.ok(ok, "DELETE /pets/5 valid: " .. tostring(err))
end)

T.done()
