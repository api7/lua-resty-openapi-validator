INST_PREFIX ?= /usr/local/openresty
INST_LUADIR ?= $(INST_PREFIX)/lualib
INSTALL ?= install

RESTY := /usr/local/openresty/bin/resty --shdict "test 1m"

UNIT_TESTS := $(sort $(wildcard t/unit/test_*.lua))
CONFORMANCE_TESTS := $(sort $(wildcard t/conformance/test_*.lua))

.PHONY: test test-unit test-conformance lint dev install clean help

### help:          Show Makefile rules
help:
	@echo Makefile rules:
	@echo
	@grep -E '^### [-A-Za-z0-9_]+:' Makefile | sed 's/###/   /'

### dev:           Create a development ENV
dev:
	luarocks install rockspec/lua-resty-openapi-validator-master-0.1-0.rockspec --only-deps --local

### install:       Install the library to runtime
install:
	$(INSTALL) -d $(INST_LUADIR)/resty/openapi_validator/
	$(INSTALL) lib/resty/openapi_validator/*.lua $(INST_LUADIR)/resty/openapi_validator/

### test:          Run all tests
test: test-unit test-conformance
	@echo "All tests passed."

### test-unit:     Run unit tests
test-unit:
	@echo "=== Unit tests ==="
	@for f in $(UNIT_TESTS); do $(RESTY) -e "dofile('$$f')" || exit 1; done

### test-conformance:  Run conformance tests
test-conformance:
	@echo "=== Conformance tests ==="
	@for f in $(CONFORMANCE_TESTS); do $(RESTY) -e "dofile('$$f')" || exit 1; done

### lint:          Lint Lua source code
lint:
	luacheck -q lib/

### clean:         Remove build artifacts
clean:
	rm -rf *.rock
