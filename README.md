# lua-resty-openapi-validator

Pure Lua OpenAPI request validator for OpenResty / LuaJIT.

Validates HTTP requests against OpenAPI 3.0 and 3.1 specifications using
[lua-resty-radixtree](https://github.com/api7/lua-resty-radixtree) for path
matching and [api7/jsonschema](https://github.com/api7/jsonschema) for schema
validation. No Go FFI or external processes required.

## Performance

**~45% higher throughput** than the Go FFI-based validator under concurrent load
(single worker, 50 connections). See [benchmark/RESULTS.md](benchmark/RESULTS.md).

## Installation

```bash
luarocks install lua-resty-openapi-validator
```

Or add the `lib/` directory to your `lua_package_path`.

### Dependencies

- [api7/jsonschema](https://github.com/api7/jsonschema) — JSON Schema Draft 4/6/7 validation
- [lua-resty-radixtree](https://github.com/api7/lua-resty-radixtree) — radix tree path routing
- [lua-cjson](https://github.com/openresty/lua-cjson) — JSON encoding/decoding

## Quick Start

```lua
local ov = require("resty.openapi_validator")

-- compile once (cache the result)
local validator, err = ov.compile(spec_json_string, {
    strict = true,       -- error on unsupported 3.1 keywords (default: true)
    coerce_types = true, -- coerce query/header string values to schema types (default: true)
    fail_fast = false,   -- return on first error (default: false)
})
if not validator then
    ngx.log(ngx.ERR, "spec compile error: ", err)
    return
end

-- validate per-request
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

### Selective Validation

Skip specific validation steps:

```lua
local ok, err = validator:validate_request(req, {
    skip_query = true,  -- skip query parameter validation
    skip_body  = true,  -- skip request body validation
})
```

## Validation Scope

| Feature | Status |
|---|---|
| Path parameter matching & validation | ✅ |
| Query parameter validation (with type coercion) | ✅ |
| Header validation | ✅ |
| Request body validation (JSON) | ✅ |
| `style` / `explode` parameter serialization | ✅ |
| `$ref` resolution (document-internal) | ✅ |
| Circular `$ref` support | ✅ |
| `allOf` / `oneOf` / `anyOf` composition | ✅ |
| `additionalProperties` | ✅ |
| OpenAPI 3.0 `nullable` | ✅ |
| OpenAPI 3.1 type arrays (`["string", "null"]`) | ✅ |
| Response validation | ❌ (not planned for v1) |
| Security scheme validation | ❌ |
| External `$ref` (URLs, files) | ❌ |
| `multipart/form-data` body | ⚠️ (skipped, returns OK) |

## OpenAPI 3.1 Support

OpenAPI 3.1 uses JSON Schema Draft 2020-12. Since the underlying jsonschema
library supports up to Draft 7, schemas are normalized at compile time:

| 3.1 / 2020-12 Feature | Normalization |
|---|---|
| `prefixItems` | → `items` (tuple form) |
| `$defs` | → `definitions` |
| `dependentRequired` / `dependentSchemas` | → `dependencies` |
| `type: ["string", "null"]` | Passed through (Draft 7 compatible) |
| `$ref` with sibling keywords | → `allOf: [resolved, {siblings}]` |
| `$dynamicRef`, `unevaluatedProperties` | Error (strict) / Warning (lenient) |

## Testing

```bash
make test
```

Runs 200 tests across unit tests and conformance tests ported from
[kin-openapi](https://github.com/getkin/kin-openapi).

## License

Apache 2.0
