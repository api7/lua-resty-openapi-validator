.PHONY: test test-unit test-conformance benchmark lint clean

RESTY := /usr/local/openresty/bin/resty --shdict "test 1m"

test: test-unit test-conformance
	@echo "All tests passed."

test-unit:
	@echo "=== Unit tests ==="
	@$(RESTY) -e 'dofile("t/unit/test_loader.lua")'
	@$(RESTY) -e 'dofile("t/unit/test_refs.lua")'
	@$(RESTY) -e 'dofile("t/unit/test_normalize.lua")'
	@$(RESTY) -e 'dofile("t/unit/test_compile.lua")'
	@$(RESTY) -e 'dofile("t/unit/test_router.lua")'
	@$(RESTY) -e 'dofile("t/unit/test_params.lua")'
	@$(RESTY) -e 'dofile("t/unit/test_body.lua")'
	@$(RESTY) -e 'dofile("t/unit/test_e2e.lua")'

test-conformance:
	@echo "=== Conformance tests ==="
	@$(RESTY) -e 'dofile("t/conformance/test_kin_openapi.lua")'

benchmark:
	@$(RESTY) -e 'dofile("benchmark/bench.lua")'

lint:
	@luacheck lib/ --std ngx_lua

clean:
	@rm -rf *.rock benchmark/logs/ benchmark/nginx.conf
