# Benchmark Results: Lua vs Go FFI OpenAPI Validator

## Environment

- **CPU**: AMD EPYC (host machine)
- **OpenResty**: 1.21.4.4
- **Worker processes**: 1
- **Tool**: wrk2 (4 threads, 50 connections, 10s duration, target 50K req/s)

## Test Scenario

- **Endpoint**: POST /users/{userId}?limit=10
- **Path param**: userId (integer, minimum 1)
- **Query param**: limit (integer, 1-100)
- **Header**: X-Request-Id (required, string)
- **Body**: ~300B JSON with 10 fields (string, integer, number, boolean, array, nested object, additionalProperties, enum, pattern)
- **Spec**: OpenAPI 3.0 with comprehensive schema constraints

## Results

| Metric | Lua Validator | Go FFI Validator | Improvement |
|---|---|---|---|
| **Throughput** | **26,993 req/s** | 18,610 req/s | **+45%** |
| **p50 Latency** | **2.33s** | 3.14s | **-35%** |
| **p99 Latency** | **4.53s** | 6.19s | **-27%** |
| **Max Latency** | **4.59s** | 6.26s | **-27%** |

> Note: High absolute latencies are due to wrk2's coordinated omission correction at a 50K req/s target rate that exceeds the server's max throughput on a single worker. The relative comparison is what matters.

## Analysis

The Lua validator achieves **~45% higher throughput** than the Go FFI version on the same spec and request payload. Key reasons:

1. **No FFI boundary crossing**: The Go FFI version serializes headers as JSON, copies body as C string, crosses the cgo boundary, then deserializes everything in Go. The Lua version operates on native Lua tables directly.

2. **No Go GC interference**: The Go runtime's garbage collector runs in the same process as OpenResty workers. Under load, GC pauses add latency variance. The Lua version runs entirely under LuaJIT's lightweight allocator.

3. **Pre-compiled validation**: The Lua version pre-compiles jsonschema validators during `compile()`. Each request only runs the pre-built validation function, with zero reflection or dynamic dispatch.

4. **Zero-copy parameters**: Path, query, and header parameters are read directly from OpenResty's request API. The Go FFI version re-parses the full URL and re-creates an `http.Request` object on every call.

## Single-thread Microbenchmark

Running 50K iterations in a tight loop (os.clock CPU time):

| Metric | Lua Validator | Go FFI Validator |
|---|---|---|
| Throughput | ~120K ops/s | ~110K ops/s |
| Avg latency | 0.008 ms/op | 0.009 ms/op |

The single-thread difference is smaller (~1.1-1.2x) because both versions avoid the concurrency-related overheads. The gap widens under concurrent load.
