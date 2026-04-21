-- OpenResty server config for benchmarking Lua vs Go FFI validator
-- Usage: openresty -p benchmark/ -c nginx.conf
-- Then: wrk -t4 -c100 -d10s -s benchmark/wrk_post.lua http://127.0.0.1:19080/lua/users/42?limit=10
--       wrk -t4 -c100 -d10s -s benchmark/wrk_post.lua http://127.0.0.1:19080/ffi/users/42?limit=10

local spec_path = os.getenv("SPEC_PATH") or "benchmark/spec.json"
local lib_path = os.getenv("LUA_VALIDATOR_LIB") or "lib"
local gateway_deps = os.getenv("GATEWAY_DEPS") or "/home/nic/GolandProjects/api7ee/gateway/deps"

local conf = string.format([[
worker_processes 1;
error_log logs/error.log warn;
pid logs/nginx.pid;

events {
    worker_connections 1024;
}

http {
    lua_shared_dict test 1m;

    lua_package_path "%s/?.lua;%s/?/init.lua;%s/share/lua/5.1/?.lua;%s/share/lua/5.1/?/init.lua;/usr/local/openresty/lualib/?.lua;;";
    lua_package_cpath "%s/lib/lua/5.1/?.so;/usr/local/openresty/lualib/?.so;;";

    init_worker_by_lua_block {
        local cjson = require("cjson.safe")
        local f = io.open("%s", "r")
        local spec_str = f:read("*a")
        f:close()

        -- compile Lua validator
        local ov = require("resty.openapi_validator")
        local v, err = ov.compile(spec_str)
        if not v then
            ngx.log(ngx.ERR, "Lua validator compile failed: ", err)
        end
        _G._lua_validator = v

        -- compile Go FFI validator
        local ok, go_v = pcall(require, "resty.validator")
        if ok and go_v then
            local id, err = go_v.register_openapi(spec_str)
            if id then
                _G._go_validator = go_v
                _G._go_openapi_id = id
                _G._go_spec_str = spec_str
                ngx.log(ngx.WARN, "Go FFI validator loaded, id=", id)
            else
                ngx.log(ngx.ERR, "Go FFI register failed: ", tostring(err))
            end
        else
            ngx.log(ngx.WARN, "Go FFI validator not available")
        end
    }

    server {
        listen 19080;

        location ~ ^/lua/(.+) {
            content_by_lua_block {
                local v = _G._lua_validator
                if not v then
                    ngx.status = 500
                    ngx.say("Lua validator not loaded")
                    return
                end

                ngx.req.read_body()
                local ok, err = v:validate_request({
                    method = ngx.req.get_method(),
                    path = "/" .. ngx.var[1],
                    query = ngx.req.get_uri_args(),
                    headers = ngx.req.get_headers(0, true),
                    body = ngx.req.get_body_data(),
                    content_type = ngx.var.content_type,
                })

                if ok then
                    ngx.status = 200
                    ngx.say("OK")
                else
                    ngx.status = 400
                    ngx.say(tostring(err))
                end
            }
        }

        location ~ ^/ffi/(.+) {
            content_by_lua_block {
                local go_v = _G._go_validator
                if not go_v then
                    ngx.status = 500
                    ngx.say("Go FFI validator not loaded")
                    return
                end

                ngx.req.read_body()
                local cjson = require("cjson.safe")
                local headers = ngx.req.get_headers(0, true)

                local ok, err = go_v.validate_request(
                    _G._go_openapi_id,
                    _G._go_spec_str,
                    ngx.req.get_method(),
                    ngx.var.request_uri:gsub("^/ffi", ""),
                    cjson.encode(headers),
                    ngx.req.get_body_data() or "",
                    false, false)

                if ok then
                    ngx.status = 200
                    ngx.say("OK")
                else
                    ngx.status = 400
                    ngx.say(tostring(err))
                end
            }
        }
    }
}
]], lib_path, lib_path, gateway_deps, gateway_deps, gateway_deps, spec_path)

-- write conf
local f = io.open("benchmark/nginx.conf", "w")
f:write(conf)
f:close()
print("Generated benchmark/nginx.conf")
