API
===

Table of Contents
=================

* [compile](#compile)
* [validate_request](#validate_request)

compile
-------

`syntax: validator, err = ov.compile(spec_str, opts)`

Compiles an OpenAPI specification JSON string into a reusable validator object.
The spec is parsed, `$ref` pointers are resolved, and schemas are normalized to
JSON Schema Draft 7. The returned validator should be cached and reused across
requests.

- `spec_str`: string — raw JSON of an OpenAPI 3.0 or 3.1 specification.
- `opts`: table (optional) — compilation options:
  - `strict`: boolean (default `true`) — if `true`, returns an error when
    unsupported OpenAPI 3.1 keywords are encountered (`$dynamicRef`,
    `unevaluatedProperties`, etc.); if `false`, these keywords are silently
    dropped with a warning.

Returns a validator object on success, or `nil` and an error string on failure.

```lua
local ov = require("resty.openapi_validator")

local validator, err = ov.compile(spec_json, { strict = true })
if not validator then
    ngx.log(ngx.ERR, "compile: ", err)
    return
end
```

[Back to TOC](#table-of-contents)

validate_request
----------------

`syntax: ok, err = validator:validate_request(req, skip)`

Validates an incoming HTTP request against the compiled OpenAPI spec. Returns
`true` on success, or `false` and a formatted error string on failure.

- `req`: table — request data with the following fields:
  - `method`: string (required) — HTTP method (e.g. `"GET"`, `"POST"`)
  - `path`: string (required) — request URI path (e.g. `"/users/123"`)
  - `query`: table (optional) — query parameters `{ name = value | {values} }`
  - `headers`: table (optional) — request headers `{ name = value }`
  - `body`: string (optional) — raw request body
  - `content_type`: string (optional) — Content-Type header value

- `skip`: table (optional) — selectively skip validation steps:
  - `path`: boolean — skip path parameter validation
  - `query`: boolean — skip query parameter validation
  - `header`: boolean — skip header validation
  - `body`: boolean — skip request body validation
  - `read_only`: boolean — skip readOnly property checks in request body
  - `write_only`: boolean — skip writeOnly property checks

```lua
local ok, err = validator:validate_request({
    method       = ngx.req.get_method(),
    path         = ngx.var.uri,
    query        = ngx.req.get_uri_args(),
    headers      = ngx.req.get_headers(0, true),
    body         = ngx.req.get_body_data(),
    content_type = ngx.var.content_type,
})

if not ok then
    ngx.status = 400
    ngx.say(err)
    return
end
```

Skip specific validation:

```lua
local ok, err = validator:validate_request(req, {
    body      = true,  -- skip body validation
    read_only = true,  -- skip readOnly checks
})
```

[Back to TOC](#table-of-contents)
