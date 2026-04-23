#!/usr/bin/env resty
--- Regression tests for the bugs surfaced by the v1.0.3 multi-spec QA pass.
-- See qa/lua-resty-openapi-validator-v1.0.3.md (in api7ee workspace).
dofile("t/lib/test_bootstrap.lua")

local T = require("test_helper")
local cjson = require("cjson.safe")
local ov = require("resty.openapi_validator")

local function compile(spec)
    local v, err = ov.compile(cjson.encode(spec))
    assert(v, "compile failed: " .. tostring(err))
    return v
end

-- Bug 1: path templates with literal extension (e.g. /users/{id}.json) used
-- to be silently misrouted by lua-resty-radixtree, which treated the whole
-- segment ":{id}.json" as a single param named "{id}.json". The validator now
-- detects mixed segments at compile time and re-extracts path params with PCRE.
T.describe("Bug 1: path with literal .json extension after param", function()
    local v = compile({
        openapi = "3.0.0",
        info = { title = "t", version = "0" },
        paths = {
            ["/users/{id}.json"] = {
                get = {
                    parameters = {
                        {
                            ["in"] = "path", name = "id", required = true,
                            schema = { type = "string", minLength = 1 },
                        },
                    },
                    responses = { ["200"] = { description = "ok" } },
                },
            },
        },
    })
    local ok, err = v:validate_request({ method = "GET", path = "/users/abc.json" })
    T.ok(ok, "valid id extracted: " .. tostring(err))

    -- and the param value really came through (not nil/empty under the wrong name)
    local ok2 = v:validate_request({ method = "GET", path = "/users/x.json" })
    T.ok(ok2, "single-char id 'x' accepted by minLength=1")
end)

-- Bug 1b: dotted suffix shouldn't be greedy-matched
T.describe("Bug 1b: param value must not consume the literal extension", function()
    local v = compile({
        openapi = "3.0.0",
        info = { title = "t", version = "0" },
        paths = {
            ["/files/{name}.txt"] = {
                get = {
                    parameters = {
                        {
                            ["in"] = "path", name = "name", required = true,
                            schema = { type = "string", pattern = "^[a-z]+$" },
                        },
                    },
                    responses = { ["200"] = { description = "ok" } },
                },
            },
        },
    })
    local ok, err = v:validate_request({ method = "GET", path = "/files/report.txt" })
    T.ok(ok, "name 'report' (not 'report.txt') extracted: " .. tostring(err))
end)

-- Bug 2: nullable + enum with explicit null in the enum list used to
-- silently disable the enum check inside api7/jsonschema (cjson.null
-- userdata leaked into the cloned schema). After normalization, any string
-- could pass as a "valid enum" value.
T.describe("Bug 2: nullable + enum with null still enforces enum", function()
    local v = compile({
        openapi = "3.0.0",
        info = { title = "t", version = "0" },
        paths = {
            ["/x"] = {
                post = {
                    requestBody = {
                        required = true,
                        content = {
                            ["application/json"] = {
                                schema = {
                                    type = "object",
                                    properties = {
                                        status = {
                                            type = "string",
                                            nullable = true,
                                            enum = { "free", "paid", cjson.null },
                                        },
                                    },
                                    required = { "status" },
                                },
                            },
                        },
                    },
                    responses = { ["200"] = { description = "ok" } },
                },
            },
        },
    })
    local ok = v:validate_request({
        method = "POST", path = "/x",
        content_type = "application/json",
        body = '{"status":"free"}',
    })
    T.ok(ok, "free is in enum")

    local ok2 = v:validate_request({
        method = "POST", path = "/x",
        content_type = "application/json",
        body = '{"status":null}',
    })
    T.ok(ok2, "null is allowed via nullable")

    local ok3, err3 = v:validate_request({
        method = "POST", path = "/x",
        content_type = "application/json",
        body = '{"status":"bogus"}',
    })
    T.ok(not ok3, "bogus is NOT in enum, must be rejected")
    -- with nullable, schema is wrapped as anyOf [original, {type:null}], so
    -- the error wording mentions "matches none of the required" rather than
    -- "enum"; either way, the request must be rejected (the regression here
    -- was silent acceptance).
    T.ok(err3 and #err3 > 0, "error message present: " .. tostring(err3))
end)

-- Bug 4: array-style query params with delimiter styles used to crash when
-- the raw value arrived as a Lua table (multi-value form input). Now coerced
-- to a delimiter-joined string before splitting.
T.describe("Bug 4: pipeDelimited param with table raw value does not crash", function()
    local v = compile({
        openapi = "3.0.0",
        info = { title = "t", version = "0" },
        paths = {
            ["/q"] = {
                get = {
                    parameters = {
                        {
                            ["in"] = "query", name = "ids", required = true,
                            style = "pipeDelimited", explode = false,
                            schema = { type = "array", items = { type = "string" } },
                        },
                    },
                    responses = { ["200"] = { description = "ok" } },
                },
            },
        },
    })
    local ok, err = v:validate_request({
        method = "GET", path = "/q",
        query = { ids = { "a|b", "c" } },
    })
    T.ok(ok, "table raw value handled: " .. tostring(err))
end)

-- Bug 5: cjson.null in content_type (e.g. caller passed a parsed JSON value
-- through verbatim) is userdata, which is truthy in Lua. The body validator
-- entered the content-type branch and crashed. Now normalized to nil at the
-- top of body.validate so all downstream sites (find_body_schema_for_content_type,
-- is_json_content_type, ...) treat it like an absent header.
T.describe("Bug 5: cjson.null content_type does not crash (with body present)", function()
    local v = compile({
        openapi = "3.0.0",
        info = { title = "t", version = "0" },
        paths = {
            ["/p"] = {
                post = {
                    requestBody = {
                        required = false,
                        content = {
                            ["application/json"] = {
                                schema = { type = "object" },
                            },
                        },
                    },
                    responses = { ["200"] = { description = "ok" } },
                },
            },
        },
    })
    -- Non-empty body so the body validator actually evaluates content_type
    -- (an empty body short-circuits before the content-type branch).
    local pcall_ok, ok, err = pcall(v.validate_request, v, {
        method = "POST", path = "/p",
        content_type = cjson.null,
        body = '{"hello":"world"}',
    })
    T.ok(pcall_ok, "cjson.null content_type didn't crash: " .. tostring(ok))
    -- With content_type normalized to nil, treated as no declared CT match;
    -- since the request has a body but the validator can't find a schema for
    -- the (absent) content-type, it should not crash. Outcome (ok or not) is
    -- secondary; the regression is the crash.
    T.ok(ok ~= nil, "validator returned a value, not a crash: ok=" .. tostring(ok) .. " err=" .. tostring(err))
end)

-- Bug 2b: nullable + const = null collapses to just {type:"null"}, which
-- means anything other than null must be rejected.
T.describe("Bug 2b: nullable + const=null only accepts null", function()
    local v = compile({
        openapi = "3.0.0",
        info = { title = "t", version = "0" },
        paths = {
            ["/c"] = {
                post = {
                    requestBody = {
                        required = true,
                        content = {
                            ["application/json"] = {
                                schema = {
                                    type = "object",
                                    properties = {
                                        v = {
                                            type = "string",
                                            nullable = true,
                                            ["const"] = cjson.null,
                                        },
                                    },
                                    required = { "v" },
                                },
                            },
                        },
                    },
                    responses = { ["200"] = { description = "ok" } },
                },
            },
        },
    })
    local ok = v:validate_request({
        method = "POST", path = "/c",
        content_type = "application/json",
        body = '{"v":null}',
    })
    T.ok(ok, "null is accepted (only allowed value)")

    local ok2 = v:validate_request({
        method = "POST", path = "/c",
        content_type = "application/json",
        body = '{"v":"anything"}',
    })
    T.ok(not ok2, "non-null rejected when const is null")
end)

T.done()
