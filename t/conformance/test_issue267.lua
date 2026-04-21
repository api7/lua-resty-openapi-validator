#!/usr/bin/env resty
--- Conformance test ported from kin-openapi issue267_test.go
-- Tests oneOf/anyOf/allOf body validation with both JSON and form-urlencoded.
dofile("t/lib/test_bootstrap.lua")

local T = require("test_helper")
local cjson = require("cjson.safe")
local ov = require("resty.openapi_validator")

local spec = cjson.encode({
    openapi = "3.0.0",
    info = { title = "sample API", version = "1.0.0" },
    paths = {
        ["/oauth2/token"] = {
            post = {
                requestBody = {
                    content = {
                        ["application/json"] = {
                            schema = { ["$ref"] = "#/components/schemas/AccessTokenRequest" },
                        },
                        ["application/x-www-form-urlencoded"] = {
                            schema = { ["$ref"] = "#/components/schemas/AccessTokenRequest" },
                        },
                    },
                },
                responses = { ["200"] = { description = "OK" } },
            },
        },
        ["/oauth2/any-token"] = {
            post = {
                requestBody = {
                    content = {
                        ["application/json"] = {
                            schema = { ["$ref"] = "#/components/schemas/AnyTokenRequest" },
                        },
                        ["application/x-www-form-urlencoded"] = {
                            schema = { ["$ref"] = "#/components/schemas/AnyTokenRequest" },
                        },
                    },
                },
                responses = { ["200"] = { description = "OK" } },
            },
        },
        ["/oauth2/all-token"] = {
            post = {
                requestBody = {
                    content = {
                        ["application/json"] = {
                            schema = { ["$ref"] = "#/components/schemas/AllTokenRequest" },
                        },
                        ["application/x-www-form-urlencoded"] = {
                            schema = { ["$ref"] = "#/components/schemas/AllTokenRequest" },
                        },
                    },
                },
                responses = { ["200"] = { description = "OK" } },
            },
        },
    },
    components = {
        schemas = {
            AccessTokenRequest = {
                type = "object",
                oneOf = {
                    { ["$ref"] = "#/components/schemas/ClientCredentialsTokenRequest" },
                    { ["$ref"] = "#/components/schemas/RefreshTokenRequest" },
                },
            },
            ClientCredentialsTokenRequest = {
                type = "object",
                properties = {
                    grant_type = { type = "string", enum = { "client_credentials" } },
                    scope = { type = "string" },
                    client_id = { type = "string" },
                    client_secret = { type = "string" },
                },
                required = { "grant_type", "scope", "client_id", "client_secret" },
            },
            RefreshTokenRequest = {
                type = "object",
                properties = {
                    grant_type = { type = "string", enum = { "refresh_token" } },
                    client_id = { type = "string" },
                    refresh_token = { type = "string" },
                },
                required = { "grant_type", "client_id", "refresh_token" },
            },
            AnyTokenRequest = {
                type = "object",
                anyOf = {
                    { ["$ref"] = "#/components/schemas/ClientCredentialsTokenRequest" },
                    { ["$ref"] = "#/components/schemas/RefreshTokenRequest" },
                    { ["$ref"] = "#/components/schemas/AdditionalTokenRequest" },
                },
            },
            AdditionalTokenRequest = {
                type = "object",
                properties = {
                    grant_type = { type = "string", enum = { "additional_grant" } },
                    additional_info = { type = "string" },
                },
                required = { "grant_type", "additional_info" },
            },
            AllTokenRequest = {
                type = "object",
                allOf = {
                    { ["$ref"] = "#/components/schemas/ClientCredentialsTokenRequest" },
                    { ["$ref"] = "#/components/schemas/TrackingInfo" },
                },
            },
            TrackingInfo = {
                type = "object",
                properties = {
                    tracking_id = { type = "string" },
                },
                required = { "tracking_id" },
            },
        },
    },
})

local v = ov.compile(spec)
assert(v, "compile failed")

-- JSON test cases
T.describe("issue267: JSON - client_credentials token (valid)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/oauth2/token",
        body = '{"grant_type":"client_credentials","scope":"testscope","client_id":"myclient","client_secret":"mypass"}',
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue267: JSON - client_credentials with extra field (valid)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/oauth2/token",
        body = '{"grant_type":"client_credentials","scope":"testscope","client_id":"myclient","client_secret":"mypass","request":1}',
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue267: JSON - anyOf client_credentials (valid)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/oauth2/any-token",
        body = '{"grant_type":"client_credentials","scope":"testscope","client_id":"myclient","client_secret":"mypass"}',
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue267: JSON - anyOf refresh_token (valid)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/oauth2/any-token",
        body = '{"grant_type":"refresh_token","client_id":"myclient","refresh_token":"someRefreshToken"}',
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue267: JSON - anyOf additional_grant (valid)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/oauth2/any-token",
        body = '{"grant_type":"additional_grant","additional_info":"extraInfo"}',
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue267: JSON - anyOf invalid_grant (fail)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/oauth2/any-token",
        body = '{"grant_type":"invalid_grant","extra_field":"extraValue"}',
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    })
    T.ok(not ok, "should fail")
end)

T.describe("issue267: JSON - allOf valid (all required fields)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/oauth2/all-token",
        body = '{"grant_type":"client_credentials","scope":"testscope","client_id":"myclient","client_secret":"mypass","tracking_id":"123456"}',
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue267: JSON - allOf invalid (missing required)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/oauth2/all-token",
        body = '{"grant_type":"invalid","client_id":"myclient","extra_field":"extraValue"}',
        content_type = "application/json",
        headers = { ["content-type"] = "application/json" },
    })
    T.ok(not ok, "should fail")
end)

-- form-urlencoded test cases
T.describe("issue267: form - client_credentials (valid)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/oauth2/token",
        body = "grant_type=client_credentials&scope=testscope&client_id=myclient&client_secret=mypass",
        content_type = "application/x-www-form-urlencoded",
        headers = { ["content-type"] = "application/x-www-form-urlencoded" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue267: form - client_credentials with extra field (valid)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/oauth2/token",
        body = "grant_type=client_credentials&scope=testscope&client_id=myclient&client_secret=mypass&request=1",
        content_type = "application/x-www-form-urlencoded",
        headers = { ["content-type"] = "application/x-www-form-urlencoded" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue267: form - invalid data (fail)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/oauth2/token",
        body = "invalid_field=invalid_value",
        content_type = "application/x-www-form-urlencoded",
        headers = { ["content-type"] = "application/x-www-form-urlencoded" },
    })
    T.ok(not ok, "should fail")
end)

T.describe("issue267: form - anyOf client_credentials (valid)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/oauth2/any-token",
        body = "grant_type=client_credentials&scope=testscope&client_id=myclient&client_secret=mypass",
        content_type = "application/x-www-form-urlencoded",
        headers = { ["content-type"] = "application/x-www-form-urlencoded" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue267: form - anyOf refresh_token (valid)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/oauth2/any-token",
        body = "grant_type=refresh_token&client_id=myclient&refresh_token=someRefreshToken",
        content_type = "application/x-www-form-urlencoded",
        headers = { ["content-type"] = "application/x-www-form-urlencoded" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue267: form - anyOf additional_grant (valid)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/oauth2/any-token",
        body = "grant_type=additional_grant&additional_info=extraInfo",
        content_type = "application/x-www-form-urlencoded",
        headers = { ["content-type"] = "application/x-www-form-urlencoded" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue267: form - anyOf invalid_grant (fail)", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/oauth2/any-token",
        body = "grant_type=invalid_grant&extra_field=extraValue",
        content_type = "application/x-www-form-urlencoded",
        headers = { ["content-type"] = "application/x-www-form-urlencoded" },
    })
    T.ok(not ok, "should fail")
end)

T.describe("issue267: form - allOf valid", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/oauth2/all-token",
        body = "grant_type=client_credentials&scope=testscope&client_id=myclient&client_secret=mypass&tracking_id=123456",
        content_type = "application/x-www-form-urlencoded",
        headers = { ["content-type"] = "application/x-www-form-urlencoded" },
    })
    T.ok(ok, "should pass: " .. tostring(err))
end)

T.describe("issue267: form - allOf invalid", function()
    local ok, err = v:validate_request({
        method = "POST",
        path = "/oauth2/all-token",
        body = "grant_type=invalid&client_id=myclient&extra_field=extraValue",
        content_type = "application/x-www-form-urlencoded",
        headers = { ["content-type"] = "application/x-www-form-urlencoded" },
    })
    T.ok(not ok, "should fail")
end)

T.done()
