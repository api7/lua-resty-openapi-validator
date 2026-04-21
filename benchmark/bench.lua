-- Benchmark: Lua OpenAPI validator vs Go FFI validator
-- Run with: resty --shdict "test 1m" benchmark/bench.lua

dofile("t/lib/test_bootstrap.lua")

local cjson = require("cjson.safe")

-- Load spec
local f = io.open("benchmark/spec.json", "r")
local spec_str = f:read("*a")
f:close()

-- Prepare test request body
local body = cjson.encode({
    name = "Alice Johnson",
    email = "alice@example.com",
    age = 30,
    role = "admin",
    active = true,
    tags = { "vip", "enterprise" },
    address = {
        street = "123 Main St",
        city = "San Francisco",
        zip = "94105",
    },
    metadata = { department = "Engineering", level = "senior" },
    score = 95.5,
    notes = "Premium customer with extended support plan.",
})

local ITERATIONS = 50000

-- ===== Benchmark: Lua validator =====
local ov = require("resty.openapi_validator")
local validator, err = ov.compile(spec_str)
assert(validator, "compile failed: " .. tostring(err))

-- warm up
for i = 1, 100 do
    validator:validate_request({
        method = "POST",
        path = "/users/42",
        query = { limit = "10" },
        headers = { ["x-request-id"] = "bench-" .. i },
        body = body,
        content_type = "application/json",
    })
end

-- benchmark
local t0 = os.clock()
for i = 1, ITERATIONS do
    local ok, err = validator:validate_request({
        method = "POST",
        path = "/users/42",
        query = { limit = "10" },
        headers = { ["x-request-id"] = "bench-" .. i },
        body = body,
        content_type = "application/json",
    })
    if not ok then
        print("ERROR at iteration " .. i .. ": " .. tostring(err))
        break
    end
end
local t1 = os.clock()
local lua_elapsed = t1 - t0
local lua_ops = ITERATIONS / lua_elapsed

print(string.format("=== Lua Validator ==="))
print(string.format("  Iterations: %d", ITERATIONS))
print(string.format("  Elapsed:    %.3f s", lua_elapsed))
print(string.format("  Throughput: %.0f ops/s", lua_ops))
print(string.format("  Avg:        %.3f ms/op", lua_elapsed / ITERATIONS * 1000))
print()

-- ===== Benchmark: Go FFI validator =====
local go_ok, go_validator = pcall(require, "resty.validator")
if go_ok and go_validator then
    -- warm up
    local openapi_id, go_err = go_validator.register_openapi(spec_str)
    if not openapi_id then
        print("Go FFI register failed: " .. tostring(go_err))
        return
    end

    for i = 1, 100 do
        local headers_json = cjson.encode({ ["x-request-id"] = "bench-" .. i })
        go_validator.validate_request(openapi_id, spec_str, "POST",
            "/users/42?limit=10", headers_json, body, false, false)
    end

    -- benchmark
    t0 = os.clock()
    for i = 1, ITERATIONS do
        local headers_json = cjson.encode({ ["x-request-id"] = "bench-" .. i })
        local ok, err = go_validator.validate_request(openapi_id, spec_str,
            "POST", "/users/42?limit=10", headers_json, body, false, false)
    end
    t1 = os.clock()
    local go_elapsed = t1 - t0
    local go_ops = ITERATIONS / go_elapsed

    print(string.format("=== Go FFI Validator ==="))
    print(string.format("  Iterations: %d", ITERATIONS))
    print(string.format("  Elapsed:    %.3f s", go_elapsed))
    print(string.format("  Throughput: %.0f ops/s", go_ops))
    print(string.format("  Avg:        %.3f ms/op", go_elapsed / ITERATIONS * 1000))
    print()

    print(string.format("=== Comparison ==="))
    print(string.format("  Lua / Go FFI speedup: %.1fx", go_elapsed / lua_elapsed))
else
    print("=== Go FFI Validator ===")
    print("  Not available (validate.so not found)")
    print("  To compare, add lua-resty-openapi-validate's lib/ and src/ to paths")
end
