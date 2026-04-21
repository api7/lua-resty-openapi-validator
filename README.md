# lua-resty-openapi-validator

Pure Lua OpenAPI request validator for OpenResty / LuaJIT.

Validates HTTP requests against OpenAPI 3.0 and 3.1 specifications without
requiring Go FFI or external processes.

## Dependencies

- [api7/jsonschema](https://github.com/api7/jsonschema) — JSON Schema Draft 4/6/7 validation
- [lua-resty-radixtree](https://github.com/api7/lua-resty-radixtree) — radix tree path routing
- [lua-cjson](https://github.com/openresty/lua-cjson) — JSON encoding/decoding

## Status

**Work in progress** — not yet production-ready.

## Quick start

```lua
local ov = require("resty.openapi_validator")

-- compile once (cache the result)
local validator, err = ov.compile(spec_json_string, {
    strict = true, -- error on unsupported 3.1 keywords
})

-- validate per-request (coming in M2-M4)
-- local ok, errs = validator:validate_request({ ... })
```

## Validation scope

- ✅ Path parameter matching and validation
- ✅ Query parameter validation (with type coercion)
- ✅ Header validation
- ✅ Request body validation (JSON)
- ❌ Response validation (not planned for v1)
- ❌ Security scheme validation

## OpenAPI 3.1 support

OpenAPI 3.1 uses JSON Schema Draft 2020-12. Since the underlying jsonschema
library supports up to Draft 7, we normalize 3.1 schemas to Draft 7 equivalents:

- `prefixItems` → `items` (tuple form)
- `$defs` → `definitions`
- `dependentRequired` / `dependentSchemas` → `dependencies`
- `type: ["string", "null"]` — passed through (Draft 7 compatible)

Keywords with no Draft 7 equivalent (`$dynamicRef`, `unevaluatedProperties`,
etc.) produce an error in strict mode or a warning in lenient mode.

## License

Apache 2.0
