.PHONY: test lint clean

LUA_PATH ?= lib/?.lua;lib/?/init.lua;;
TEST_NGINX_CWD ?= $(shell pwd)

test:
	@echo "Running tests..."
	@prove -r t/ --timer

lint:
	@echo "Linting..."
	@luacheck lib/ --std ngx_lua

clean:
	@echo "Cleaning..."
	@rm -rf *.rock
