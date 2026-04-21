--- Test environment bootstrap.
-- Sets up package paths for all test files so they can find:
-- 1. The library under test (lib/)
-- 2. Test helpers (t/lib/)
-- 3. Gateway dependencies (radixtree, jsonschema, etc.)
-- 4. OpenResty built-in libs (cjson, etc.)

local GATEWAY_DEPS = os.getenv("GATEWAY_DEPS")
                     or "/home/nic/GolandProjects/api7ee/gateway/deps"

package.path = "lib/?.lua;lib/?/init.lua;t/lib/?.lua;"
             .. GATEWAY_DEPS .. "/share/lua/5.1/?.lua;"
             .. GATEWAY_DEPS .. "/share/lua/5.1/?/init.lua;"
             .. (package.path or "")

package.cpath = GATEWAY_DEPS .. "/lib/lua/5.1/?.so;"
              .. "/usr/local/openresty/lualib/?.so;"
              .. (package.cpath or "")
