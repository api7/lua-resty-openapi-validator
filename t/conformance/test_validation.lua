#!/usr/bin/env resty
--- Conformance tests ported from kin-openapi openapi3filter/validation_test.go
-- Covers TestFilter and TestValidateRequestBody scenarios.
dofile("t/lib/test_bootstrap.lua")

local T = require("test_helper")
local cjson = require("cjson.safe")
local ov = require("resty.openapi_validator")

-- ============================================================
-- TestFilter spec
-- ============================================================

local complexArgSchema = {
    type = "object",
    required = { "name", "id" },
    properties = {
        name = { type = "string" },
        id   = { type = "string", maxLength = 2 },
    },
}

local filter_spec = {
    openapi = "3.0.0",
    info = { title = "MyAPI", version = "0.1" },
    paths = {
        ["/prefix/{pathArg}/suffix"] = {
            post = {
                parameters = {
                    { name = "pathArg", ["in"] = "path",
                      schema = { type = "string", maxLength = 2 },
                      required = true },
                    { name = "queryArg", ["in"] = "query",
                      schema = { type = "string", maxLength = 2 } },
                    -- NOTE: kin-openapi uses format:"date-time" but our jsonschema
                    -- lib doesn't enforce format. We use minLength=20 as a proxy for
                    -- "long date-time string" to test the same anyOf/oneOf/allOf logic.
                    { name = "queryArgAnyOf", ["in"] = "query",
                      schema = {
                          anyOf = {
                              { type = "string", maxLength = 2 },
                              { type = "string", minLength = 20 },
                          },
                      } },
                    { name = "queryArgOneOf", ["in"] = "query",
                      schema = {
                          oneOf = {
                              { type = "string", maxLength = 2 },
                              { type = "integer" },
                          },
                      } },
                    { name = "queryArgAllOf", ["in"] = "query",
                      schema = {
                          allOf = {
                              { type = "string", minLength = 20 },
                              { type = "string" },
                          },
                      } },
                    { name = "contentArg", ["in"] = "query",
                      content = {
                          ["application/json"] = {
                              schema = complexArgSchema,
                          },
                      } },
                },
                responses = { ["200"] = { description = "OK" } },
            },
        },
        ["/issue151"] = {
            get = {
                responses = { ["200"] = { description = "OK" } },
            },
            parameters = {
                { name = "par1", ["in"] = "query",
                  required = true,
                  schema = { type = "integer" } },
            },
        },
    },
}

local filter_v = ov.compile(cjson.encode(filter_spec))

-- 1. Valid path param "v"
T.describe("TestFilter: valid path param", function()
    local ok, err = filter_v:validate_request({
        method = "POST",
        path   = "/prefix/v/suffix",
    })
    T.ok(ok, "path param 'v' passes validation")
    T.is(err, nil, "no error for valid path param")
end)

-- 2. Path param exceeds maxLength
T.describe("TestFilter: path param exceeds maxLength", function()
    local ok, err = filter_v:validate_request({
        method = "POST",
        path   = "/prefix/EXCEEDS_MAX_LENGTH/suffix",
    })
    T.ok(not ok, "path param 'EXCEEDS_MAX_LENGTH' fails")
    T.isnt(err, nil, "error returned for too-long path param")
end)

-- 3. Valid query param
T.describe("TestFilter: valid query param", function()
    local ok, err = filter_v:validate_request({
        method = "POST",
        path   = "/prefix/v/suffix",
        query  = { queryArg = "a" },
    })
    T.ok(ok, "queryArg='a' passes")
    T.is(err, nil, "no error for valid query param")
end)

-- 4. Query param exceeds maxLength
T.describe("TestFilter: query param exceeds maxLength", function()
    local ok, err = filter_v:validate_request({
        method = "POST",
        path   = "/prefix/v/suffix",
        query  = { queryArg = "EXCEEDS_MAX_LENGTH" },
    })
    T.ok(not ok, "queryArg='EXCEEDS_MAX_LENGTH' fails")
    T.isnt(err, nil, "error for too-long query param")
end)

-- 5. Missing required query param par1 on /issue151
T.describe("TestFilter: missing required query param par1", function()
    local ok, err = filter_v:validate_request({
        method = "GET",
        path   = "/issue151",
        query  = { par2 = "par1_is_missing" },
    })
    T.ok(not ok, "missing required par1 fails")
    T.isnt(err, nil, "error for missing required query param")
end)

-- 6. anyOf/oneOf/allOf valid combo
T.describe("TestFilter: anyOf/oneOf/allOf valid combo", function()
    local ok, err = filter_v:validate_request({
        method = "POST",
        path   = "/prefix/v/suffix",
        query  = {
            queryArgAnyOf = "ae",        -- matches maxLength=2
            queryArgOneOf = "ac",        -- matches maxLength=2 string (not integer)
            queryArgAllOf = "2017-12-31T11:59:59Z",  -- len=20, matches both allOf branches
        },
    })
    T.ok(ok, "valid anyOf/oneOf/allOf combo passes")
    T.is(err, nil, "no error")
end)

-- 7. anyOf with long string (matches minLength=20 branch)
T.describe("TestFilter: anyOf with long string", function()
    local ok, err = filter_v:validate_request({
        method = "POST",
        path   = "/prefix/v/suffix",
        query  = { queryArgAnyOf = "2017-12-31T11:59:59Z" },  -- len=20
    })
    T.ok(ok, "anyOf long string passes (matches minLength=20)")
    T.is(err, nil, "no error")
end)

-- 8. anyOf with "123" (too long for maxLength=2, too short for minLength=20)
T.describe("TestFilter: anyOf '123' fails", function()
    local ok, err = filter_v:validate_request({
        method = "POST",
        path   = "/prefix/v/suffix",
        query  = { queryArgAnyOf = "123" },
    })
    T.ok(not ok, "anyOf '123' fails (matches neither branch)")
    T.isnt(err, nil, "error returned")
end)

-- 9. oneOf: integer-like string matches neither branch correctly
--    (string "2017-12-31T11:59:59Z" is too long for maxLength=2, not an integer)
T.describe("TestFilter: oneOf long string fails", function()
    local ok, err = filter_v:validate_request({
        method = "POST",
        path   = "/prefix/v/suffix",
        query  = { queryArgOneOf = "2017-12-31T11:59:59Z" },
    })
    T.ok(not ok, "oneOf long string fails (matches neither)")
    T.isnt(err, nil, "error returned")
end)

-- 10. allOf with short string (fails minLength=20)
T.describe("TestFilter: allOf short string fails", function()
    local ok, err = filter_v:validate_request({
        method = "POST",
        path   = "/prefix/v/suffix",
        query  = { queryArgAllOf = "abdfg" },
    })
    T.ok(not ok, "allOf short string fails (minLength=20 not met)")
    T.isnt(err, nil, "error returned")
end)

-- 11. Content-encoded JSON query param valid
T.describe("TestFilter: contentArg valid JSON", function()
    local ok, err = filter_v:validate_request({
        method = "POST",
        path   = "/prefix/v/suffix",
        query  = { contentArg = '{"name":"bob","id":"a"}' },
    })
    T.ok(ok, "contentArg with short id passes")
    T.is(err, nil, "no error")
end)

-- 12. Content-encoded JSON query param invalid (id too long)
T.describe("TestFilter: contentArg invalid JSON", function()
    local ok, err = filter_v:validate_request({
        method = "POST",
        path   = "/prefix/v/suffix",
        query  = { contentArg = '{"name":"bob","id":"EXCEEDS_MAX_LENGTH"}' },
    })
    T.ok(not ok, "contentArg with too-long id fails")
    T.isnt(err, nil, "error returned")
end)

-- ============================================================
-- TestValidateRequestBody
-- ============================================================

-- Helper: build a minimal spec wrapping a requestBody definition
local function body_spec(request_body)
    return cjson.encode({
        openapi = "3.0.0",
        info = { title = "BodyTest", version = "0.1" },
        paths = {
            ["/test"] = {
                post = {
                    requestBody = request_body,
                    responses = { ["200"] = { description = "OK" } },
                },
            },
        },
    })
end

-- 1. Non-required empty body → OK
T.describe("TestValidateRequestBody: non-required empty body", function()
    local spec = body_spec({
        content = {
            ["application/json"] = {
                schema = { type = "string" },
            },
        },
    })
    local v = ov.compile(spec)
    local ok, err = v:validate_request({
        method = "POST",
        path   = "/test",
    })
    T.ok(ok, "non-required empty body passes")
    T.is(err, nil, "no error")
end)

-- 2. Non-required with body → OK
T.describe("TestValidateRequestBody: non-required with body", function()
    local spec = body_spec({
        content = {
            ["application/json"] = {
                schema = { type = "string" },
            },
        },
    })
    local v = ov.compile(spec)
    local ok, err = v:validate_request({
        method = "POST",
        path   = "/test",
        headers = { ["content-type"] = "application/json" },
        body = cjson.encode("foo"),
        content_type = "application/json",
    })
    T.ok(ok, "non-required with body passes")
    T.is(err, nil, "no error")
end)

-- 3. Required empty body → error
T.describe("TestValidateRequestBody: required empty body", function()
    local spec = body_spec({
        required = true,
        content = {
            ["application/json"] = {
                schema = { type = "string" },
            },
        },
    })
    local v = ov.compile(spec)
    local ok, err = v:validate_request({
        method = "POST",
        path   = "/test",
    })
    T.ok(not ok, "required empty body fails")
    T.isnt(err, nil, "error for missing required body")
end)

-- 4. Required with body → OK
T.describe("TestValidateRequestBody: required with body", function()
    local spec = body_spec({
        required = true,
        content = {
            ["application/json"] = {
                schema = { type = "string" },
            },
        },
    })
    local v = ov.compile(spec)
    local ok, err = v:validate_request({
        method = "POST",
        path   = "/test",
        headers = { ["content-type"] = "application/json" },
        body = cjson.encode("foo"),
        content_type = "application/json",
    })
    T.ok(ok, "required with body passes")
    T.is(err, nil, "no error")
end)

-- 5. Not JSON data (text/plain) → OK (we skip non-JSON body validation)
T.describe("TestValidateRequestBody: text/plain body", function()
    local spec = body_spec({
        required = true,
        content = {
            ["text/plain"] = {
                schema = { type = "string" },
            },
        },
    })
    local v = ov.compile(spec)
    local ok, err = v:validate_request({
        method = "POST",
        path   = "/test",
        headers = { ["content-type"] = "text/plain" },
        body = "foo",
        content_type = "text/plain",
    })
    T.ok(ok, "text/plain body passes (non-JSON skipped)")
    T.is(err, nil, "no error")
end)

-- 6. Not declared content → OK (lenient)
T.describe("TestValidateRequestBody: undeclared content type", function()
    local spec = body_spec({
        required = true,
    })
    local v = ov.compile(spec)
    local ok, err = v:validate_request({
        method = "POST",
        path   = "/test",
        headers = { ["content-type"] = "application/json" },
        body = cjson.encode("foo"),
        content_type = "application/json",
    })
    T.ok(ok, "undeclared content passes (lenient)")
    T.is(err, nil, "no error")
end)

-- 7. Not declared schema → OK
T.describe("TestValidateRequestBody: no schema declared", function()
    local spec = body_spec({
        content = {
            ["application/json"] = {},
        },
    })
    local v = ov.compile(spec)
    local ok, err = v:validate_request({
        method = "POST",
        path   = "/test",
        headers = { ["content-type"] = "application/json" },
        body = cjson.encode("foo"),
        content_type = "application/json",
    })
    T.ok(ok, "no schema declared passes")
    T.is(err, nil, "no error")
end)

T.done()
