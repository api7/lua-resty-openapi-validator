.PHONY: test test-unit test-conformance benchmark lint clean

RESTY := /usr/local/openresty/bin/resty --shdict "test 1m"

UNIT_TESTS := $(sort $(wildcard t/unit/test_*.lua))
CONFORMANCE_TESTS := $(sort $(wildcard t/conformance/test_*.lua))

test: test-unit test-conformance
	@echo "All tests passed."

test-unit:
	@echo "=== Unit tests ==="
	@for f in $(UNIT_TESTS); do $(RESTY) -e "dofile('$$f')" || exit 1; done

test-conformance:
	@echo "=== Conformance tests ==="
	@for f in $(CONFORMANCE_TESTS); do $(RESTY) -e "dofile('$$f')" || exit 1; done

benchmark:
	@$(RESTY) -e 'dofile("benchmark/bench.lua")'

lint:
	@luacheck lib/ --std ngx_lua

clean:
	@rm -rf *.rock benchmark/logs/ benchmark/nginx.conf
