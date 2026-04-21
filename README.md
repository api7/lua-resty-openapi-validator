Name
====

lua-resty-openapi-validator - Pure Lua OpenAPI request validator for OpenResty / LuaJIT.

![CI](https://github.com/api7/lua-resty-openapi-validator/actions/workflows/test.yml/badge.svg)
![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)

Table of Contents
=================

* [Description](#description)
* [Install](#install)
* [Quick Start](#quick-start)
* [API](api.md)
* [Validation Scope](#validation-scope)
* [OpenAPI 3.1 Support](#openapi-31-support)
* [Benchmark](#benchmark)
* [Testing](#testing)

Description
===========

Validates HTTP requests against OpenAPI 3.0 and 3.1 specifications using
[lua-resty-radixtree](https://github.com/api7/lua-resty-radixtree) for path
matching and [api7/jsonschema](https://github.com/api7/jsonschema) for schema
validation. No Go FFI or external processes required.

Install
=======

> Dependencies

- [api7/jsonschema](https://github.com/api7/jsonschema) — JSON Schema Draft 4/6/7 validation
- [lua-resty-radixtree](https://github.com/api7/lua-resty-radixtree) — radix tree path routing
- [lua-cjson](https://github.com/openresty/lua-cjson) — JSON encoding/decoding

> install by luarocks

```shell
luarocks install lua-resty-openapi-validator
```

> install by source

```shell
$ git clone https://github.com/api7/lua-resty-openapi-validator.git
$ cd lua-resty-openapi-validator
$ make dev
$ sudo make install
```

[Back to TOC](#table-of-contents)

Quick Start
===========

```lua
local ov = require("resty.openapi_validator")

-- compile once (cache the result)
local validator, err = ov.compile(spec_json_string, {
    strict = true,  -- error on unsupported 3.1 keywords (default: true)
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

See [API documentation](api.md) for details on all methods and options.

[Back to TOC](#table-of-contents)

Validation Scope
================

| Feature | Status |
|---|---|
| Path parameter matching & validation | ✅ |
| Query parameter validation (with type coercion) | ✅ |
| Header validation | ✅ |
| Request body validation (JSON) | ✅ |
| Request body validation (form-urlencoded) | ✅ |
| `style` / `explode` parameter serialization | ✅ |
| `$ref` resolution (document-internal) | ✅ |
| Circular `$ref` support | ✅ |
| `allOf` / `oneOf` / `anyOf` composition | ✅ |
| `additionalProperties` | ✅ |
| OpenAPI 3.0 `nullable` | ✅ |
| OpenAPI 3.1 type arrays (`["string", "null"]`) | ✅ |
| `readOnly` / `writeOnly` validation | ✅ |
| Response validation | ❌ (not planned for v1) |
| Security scheme validation | ❌ |
| External `$ref` (URLs, files) | ❌ |
| `multipart/form-data` body | ⚠️ basic support |

[Back to TOC](#table-of-contents)

OpenAPI 3.1 Support
===================

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

[Back to TOC](#table-of-contents)

Benchmark
=========

**~45% higher throughput** than the Go FFI-based validator under concurrent load
(single worker, 50 connections). See [benchmark/RESULTS.md](benchmark/RESULTS.md).

[Back to TOC](#table-of-contents)

Testing
=======

```shell
make test
```

Runs unit tests and conformance tests ported from
[kin-openapi](https://github.com/getkin/kin-openapi).

[Back to TOC](#table-of-contents)

License
=======

Apache 2.0
