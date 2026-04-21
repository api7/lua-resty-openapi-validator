#!/usr/bin/env resty
--- Conformance test: parameter serialization across style × explode × type.
-- Data-driven tests covering all supported serialization combinations.
dofile("t/lib/test_bootstrap.lua")

local T    = require("test_helper")
local cjson = require("cjson.safe")
local ov   = require("resty.openapi_validator")


local function make_spec(param_def, location)
    local path_template
    if location == "path" then
        path_template = "/test/{" .. param_def.name .. "}"
        param_def.required = true
    else
        path_template = "/test"
    end

    return cjson.encode({
        openapi = "3.0.0",
        info = { title = "ParamTest", version = "0.1" },
        paths = {
            [path_template] = {
                get = {
                    parameters = { param_def },
                    responses = { ["200"] = { description = "OK" } },
                },
            },
        },
    })
end


local function build_request(location, param_name, value)
    local req = { method = "GET" }

    if location == "path" then
        req.path = "/test/" .. tostring(value)
    elseif location == "query" then
        req.path = "/test"
        if type(value) == "table" then
            req.query = value
        else
            req.query = { [param_name] = value }
        end
    elseif location == "header" then
        req.path = "/test"
        req.headers = { [param_name] = value }
    end

    return req
end


-- ────────────────────────────────────────────────
-- Positive test cases
-- ────────────────────────────────────────────────

local positive_cases = {
    -- QUERY: form
    {
        "query form explode=false array",
        "query", "form", false,
        { type = "array", items = { type = "string" } },
        "a,b,c",
    },
    {
        "query form explode=true array (repeated keys)",
        "query", "form", true,
        { type = "array", items = { type = "string" } },
        { colors = { "a", "b", "c" } },   -- table → query map
    },
    {
        "query form explode=false string",
        "query", "form", false,
        { type = "string" },
        "hello",
    },
    {
        "query form explode=false integer",
        "query", "form", false,
        { type = "integer" },
        "42",
    },
    {
        "query form explode=true string",
        "query", "form", true,
        { type = "string" },
        "hello",
    },
    {
        "query form explode=true integer",
        "query", "form", true,
        { type = "integer" },
        "42",
    },
    -- QUERY: pipeDelimited
    {
        "query pipeDelimited explode=false array",
        "query", "pipeDelimited", false,
        { type = "array", items = { type = "string" } },
        "a|b|c",
    },
    -- QUERY: spaceDelimited
    {
        "query spaceDelimited explode=false array",
        "query", "spaceDelimited", false,
        { type = "array", items = { type = "string" } },
        "a b c",
    },
    -- QUERY: deepObject
    {
        "query deepObject explode=true object",
        "query", "deepObject", true,
        { type = "object", properties = { key1 = { type = "string" }, key2 = { type = "string" } } },
        { ["filter[key1]"] = "val1", ["filter[key2]"] = "val2" },
    },
    -- PATH: simple
    {
        "path simple explode=false string",
        "path", "simple", false,
        { type = "string" },
        "hello",
    },
    {
        "path simple explode=false integer",
        "path", "simple", false,
        { type = "integer" },
        "42",
    },
    {
        "path simple explode=false array",
        "path", "simple", false,
        { type = "array", items = { type = "string" } },
        "a,b,c",
    },
    {
        "path simple explode=true array",
        "path", "simple", true,
        { type = "array", items = { type = "string" } },
        "a,b,c",
    },
    {
        "path simple explode=false object",
        "path", "simple", false,
        { type = "object", properties = { k1 = { type = "string" }, k2 = { type = "string" } } },
        "k1,v1,k2,v2",
    },
    {
        "path simple explode=true object",
        "path", "simple", true,
        { type = "object", properties = { k1 = { type = "string" }, k2 = { type = "string" } } },
        "k1=v1,k2=v2",
    },
    -- HEADER: simple
    {
        "header simple explode=false string",
        "header", "simple", false,
        { type = "string" },
        "hello",
    },
    {
        "header simple explode=false integer",
        "header", "simple", false,
        { type = "integer" },
        "42",
    },
    {
        "header simple explode=false array",
        "header", "simple", false,
        { type = "array", items = { type = "string" } },
        "a,b,c",
    },
    {
        "header simple explode=true array",
        "header", "simple", true,
        { type = "array", items = { type = "string" } },
        "a,b,c",
    },
    -- QUERY: integer array coercion
    {
        "query form explode=false integer array",
        "query", "form", false,
        { type = "array", items = { type = "integer" } },
        "1,2,3",
    },
}


-- ────────────────────────────────────────────────
-- Negative test cases
-- ────────────────────────────────────────────────

local negative_cases = {
    {
        "query integer array with non-integer value",
        "query", "form", false,
        { type = "array", items = { type = "integer" } },
        "1,abc,3",
    },
    {
        "query required param missing",
        "query", "form", false,
        { type = "string" },
        nil,  -- signals missing param
        true, -- mark param required
    },
    {
        "query enum violation in array items",
        "query", "form", false,
        { type = "array", items = { type = "string", enum = { "red", "green", "blue" } } },
        "red,yellow,blue",
    },
    {
        "query object with wrong property type",
        "query", "form", false,
        { type = "object",
          properties = { count = { type = "integer" }, name = { type = "string" } },
          required = { "count" } },
        "count,notanumber,name,test",
    },
    {
        "path integer param with string value",
        "path", "simple", false,
        { type = "integer" },
        "not_a_number",
    },
    {
        "path required param missing (no match)",
        "path", "simple", false,
        { type = "string" },
        nil,
        true,
    },
    {
        "header integer with non-integer value",
        "header", "simple", false,
        { type = "integer" },
        "abc",
    },
}


-- ────────────────────────────────────────────────
-- Run positive cases
-- ────────────────────────────────────────────────

for _, tc in ipairs(positive_cases) do
    local desc, location, style, explode, schema, input = tc[1], tc[2], tc[3], tc[4], tc[5], tc[6]

    T.describe(desc, function()
        local param_name = (location == "query" and style == "deepObject")
                           and "filter" or "colors"

        local param_def = {
            name    = param_name,
            ["in"]  = location,
            style   = style,
            explode = explode,
            schema  = schema,
        }
        if location == "path" then
            param_def.required = true
        end

        local spec_str = make_spec(param_def, location)
        local validator, compile_err = ov.compile(spec_str)
        T.ok(validator ~= nil, desc .. " compiles: " .. tostring(compile_err))
        if not validator then return end

        local req = build_request(location, param_name, input)
        local ok, err = validator:validate_request(req)
        T.ok(ok, desc .. " passes: " .. tostring(err))
    end)
end


-- ────────────────────────────────────────────────
-- Run negative cases
-- ────────────────────────────────────────────────

for _, tc in ipairs(negative_cases) do
    local desc, location, style, explode, schema, input =
        tc[1], tc[2], tc[3], tc[4], tc[5], tc[6]
    local force_required = tc[7]

    T.describe(desc, function()
        local param_name = "colors"
        local param_def = {
            name    = param_name,
            ["in"]  = location,
            style   = style,
            explode = explode,
            schema  = schema,
            required = true,
        }

        local spec_str = make_spec(param_def, location)
        local validator, compile_err = ov.compile(spec_str)
        T.ok(validator ~= nil, desc .. " compiles: " .. tostring(compile_err))
        if not validator then return end

        if input == nil and location == "path" then
            -- path param missing means the path won't match at all
            local ok, err = validator:validate_request({
                method = "GET",
                path   = "/test",
            })
            T.ok(not ok, desc .. " fails: " .. tostring(err))
        elseif input == nil then
            local ok, err = validator:validate_request({
                method = "GET",
                path   = "/test",
                query  = {},
            })
            T.ok(not ok, desc .. " fails: " .. tostring(err))
        else
            local req = build_request(location, param_name, input)
            local ok, err = validator:validate_request(req)
            T.ok(not ok, desc .. " fails: " .. tostring(err))
        end
    end)
end


T.done()
