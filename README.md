[![Static analysis](https://github.com/ligurio/molly/actions/workflows/check.yaml/badge.svg)](https://github.com/ligurio/molly/actions/workflows/check.yaml)
[![Testing](https://github.com/ligurio/molly/actions/workflows/test.yaml/badge.svg)](https://github.com/ligurio/molly/actions/workflows/test.yaml)
[![Coverage Status](https://coveralls.io/repos/github/ligurio/molly/badge.svg)](https://coveralls.io/github/ligurio/molly)
[![Luarocks](https://img.shields.io/luarocks/v/ligurio/molly/scm-1)](https://luarocks.org/modules/ligurio/molly)

## Molly

is a framework for distributed systems verification, with fault injection.

### Prerequisites

- Lua interpreter: LuaJIT or LuaJIT-based is recommended.
- [luafun](https://luafun.github.io/) - Lua functional library, built-in into
  Tarantool.
- [lua-cjson](https://github.com/mpx/lua-cjson) - Lua library for fast JSON
  encoding and decoding, built-in into Tarantool.
- (optional) Jepsen-compatible consistency checker. For example
  [elle-cli](https://github.com/ligurio/elle-cli), based on Jepsen, Elle and
  Knossos.

### Installation

- Download and setup Lua interpreter, [LuaJIT](https://luajit.org/install.html)
  or LuaJIT-based is recommended (for example
  [Tarantool](https://www.tarantool.io/download/)).
- Install library using LuaRocks:

```sh
$ luarocks install --local molly
```

NOTE: Installation of modules `luafun` and `lua-cjson` is not required when
Tarantool is used, both modules are built-in there. Install them manually in
case of using LuaJIT:

```sh
$ make deps-runtime
```

### Documentation

See documentation in https://ligurio.github.io/molly/.

### Examples

See also an examples in [test/examples/](/test/examples/) for SQLite database
engine:
- `sqlite-rw-register.lua` contains a simple test that concurrently runs `get`
  and `set` operations on SQLite DB
- `sqlite-list-append.lua` contains a simple test that concurrently runs `read`
  and `append` operations on SQLite DB

For running examples you need installed an SQLite development package and
[LuaRocks](https://github.com/luarocks/luarocks/wiki/Download).

```sh
$ sudo apt install -y sqlite3 libsqlite3-dev
$ make deps
$ make test-example
```

Example produces two files with history: `history.txt` and `history.json`. With
[elle-cli](https://github.com/ligurio/elle-cli#usage) history can be checked
for consistency:

```sh
$ VER=0.1.4
$ curl -O -L https://github.com/ligurio/elle-cli/releases/download/${VER}/elle-cli-bin-${VER}.zip
$ unzip elle-cli-bin-${VER}.zip
$ java -jar ./target/elle-cli-${VER}-standalone.jar -m elle-rw-register history.json
history.json        true
```

See tests that uses Molly library in https://github.com/ligurio/molly-tests.

### Hacking

For developing `molly` you need to install: either LuaJIT or LuaJIT-based
and [LuaRocks](https://github.com/luarocks/luarocks/wiki/Download).

```sh
$ make deps
$ export PATH=$PATH:$(luarocks path --lr-bin)
$ make check
$ make test
```

You are ready to make patches!

### License

Copyright © 2021-2023 [Sergey Bronnikov](https://bronevichok.ru/)

Distributed under the ISC License.
