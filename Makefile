# This way everything works as expected ever for
# `make -C /path/to/project` or
# `make -f /path/to/project/Makefile`.
MAKEFILE_PATH := $(abspath $(lastword $(MAKEFILE_LIST)))
PROJECT_DIR := $(patsubst %/,%,$(dir $(MAKEFILE_PATH)))

LUACOV_REPORT := $(PROJECT_DIR)/luacov.report.out
LUACOV_STATS := $(PROJECT_DIR)/luacov.stats.out

CLEANUP_FILES  = ${LUACOV_STATS}
CLEANUP_FILES += ${LUACOV_REPORT}
CLEANUP_FILES += history.txt
CLEANUP_FILES += history.json

TEST_FILES ?= test/tests.lua

TARANTOOL_BIN ?= /usr/bin/tarantool
LUAJIT_BIN ?= /usr/bin/luajit

LUA_PATH ?= "?/init.lua;./?.lua;$(shell luarocks path --lr-path)"
LUA_CPATH ?= "$(shell luarocks path --lr-cpath)"

DEV ?= OFF

all: check test

doc:
	@ldoc -c $(PROJECT_DIR)/doc/config.ld -v \
              -d $(PROJECT_DIR)/doc/html/ \
                 $(PROJECT_DIR)/molly

deps: deps-runtime deps-dev

deps-dev:
	@echo "Setup development dependencies"
	luarocks install --local luacheck 1.2.0
	luarocks install --local luacov 0.15.0
	luarocks install --local cluacov 0.1.1
	luarocks install --local luacov-coveralls 0.2.3
	luarocks install --local ldoc 1.4.2
	luarocks install --local lsqlite3 0.9.5

deps-runtime:
	@echo "Setup runtime dependencies"
	luarocks install --local lua-cjson 2.1.0.10-1
	luarocks install --local https://raw.githubusercontent.com/luafun/luafun/master/fun-scm-1.rockspec
	luarocks make --local molly-scm-1.rockspec

install:
	@install -d -m 755 $(LUADIR)/molly
	@install -m 644 $(PROJECT_DIR)/molly/*.lua \
		        $(LUADIR)/molly
	@install -d -m 755 $(LUADIR)/molly/compat
	@install -m 644 $(PROJECT_DIR)/molly/compat/*.lua \
		        $(LUADIR)/molly/compat

check: luacheck

luacheck:
	@luacheck --config $(PROJECT_DIR)/.luacheckrc --codes $(PROJECT_DIR)

test-example:
	@echo "Run SQLite examples with Tarantool"
	@$(TARANTOOL_BIN) test/examples/sqlite-rw-register.lua
	@$(TARANTOOL_BIN) test/examples/sqlite-list-append.lua

test-tarantool:
	@echo "Run regression tests with Tarantool"
	@DEV=$(DEV) $(TARANTOOL_BIN) $(TEST_FILES)

test-luajit:
	@echo "Run regression tests with LuaJIT"
	@DEV=$(DEV) LUA_PATH=$(LUA_PATH) LUA_CPATH=$(LUA_CPATH) $(LUAJIT_BIN) $(TEST_FILES)

test: test-tarantool test-luajit

$(LUACOV_STATS): test-tarantool test-example

coverage: $(LUACOV_STATS)
	@sed -i -e 's@'"$$(realpath .)"'/@@' $(LUACOV_STATS)
	@cd $(PROJECT_DIR) && luacov ^molly
	@grep -A999 '^Summary' $(LUACOV_REPORT)

coveralls: coverage
	@echo "Send code coverage data to the coveralls.io service"
	@luacov-coveralls --include ^molly --verbose --repo-token ${GITHUB_TOKEN}

clean:
	@rm -f ${CLEANUP_FILES}

.PHONY: test test-example test-tarantool test-luajit install coveralls coverage
.PHONY: luacheck check doc deps-dev deps-runtime deps
