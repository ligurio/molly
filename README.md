[![Static analysis](https://github.com/ligurio/molly/actions/workflows/check.yaml/badge.svg)](https://github.com/ligurio/molly/actions/workflows/check.yaml)
[![Testing](https://github.com/ligurio/molly/actions/workflows/test.yaml/badge.svg)](https://github.com/ligurio/molly/actions/workflows/test.yaml)
[![Coverage Status](https://coveralls.io/repos/github/ligurio/molly/badge.svg)](https://coveralls.io/github/ligurio/molly)
[![Luarocks](https://img.shields.io/luarocks/v/ligurio/molly/scm-1)](https://luarocks.org/modules/ligurio/molly)

## Molly

is a framework for distributed systems verification, with fault injection.

### Prerequisites

- Lua interpreter: LuaJIT or a LuaJIT-based runtime is recommended (for
  example, Tarantool).
- [luafun](https://luafun.github.io/) - Lua functional library, built-in into
  Tarantool.
- [lua-cjson](https://github.com/mpx/lua-cjson) - Lua library for fast JSON
  encoding and decoding, built-in into Tarantool.
- (optional) a Jepsen-compatible consistency checker. For example,
  [elle-cli](https://github.com/ligurio/elle-cli), based on Jepsen, Elle and
  Knossos.

### Installation

- Download and set up a Lua interpreter. [LuaJIT](https://luajit.org/install.html)
  or a LuaJIT-based runtime is recommended (for example,
  [Tarantool](https://www.tarantool.io/download/)).
- Install the library using LuaRocks:

```sh
$ luarocks install --local molly
```

NOTE: Installing the `luafun` and `lua-cjson` modules is not required when
Tarantool is used because both are built in. Install them manually when using
LuaJIT:

```sh
$ make deps-runtime
```

### Documentation

See the documentation at https://ligurio.github.io/molly/.

### Examples

See also SQLite examples in [test/examples/](/test/examples/):
- `sqlite-rw-register.lua` contains a simple test that concurrently runs `get`
  and `set` operations on a SQLite database
- `sqlite-list-append.lua` contains a simple test that concurrently runs `read`
  and `append` operations on a SQLite database

For running examples you need installed an SQLite development package and
[LuaRocks](https://github.com/luarocks/luarocks/wiki/Download).

```sh
$ sudo apt install -y sqlite3 libsqlite3-dev
$ make deps
$ make test-example
```

The example produces two history files: `history.txt` and `history.json`. The
history can be checked for consistency with
[elle-cli](https://github.com/ligurio/elle-cli#usage):

```sh
$ VER=0.1.8
$ curl -O -L https://github.com/ligurio/elle-cli/releases/download/${VER}/elle-cli-bin-${VER}.zip
$ unzip elle-cli-bin-${VER}.zip
$ java -jar ./target/elle-cli-${VER}-standalone.jar -m elle-rw-register history.json
history.json        true
```

See the tests that use the Molly library in
https://github.com/ligurio/molly-tests.

### Hacking

To develop `molly`, install either LuaJIT or a LuaJIT-based runtime, and
[LuaRocks](https://github.com/luarocks/luarocks/wiki/Download).

```sh
$ make deps
$ export PATH=$PATH:$(luarocks path --lr-bin)
$ make check
$ make test
```

You are ready to make patches!

### License

Copyright © 2021-2026 [Sergey Bronnikov](https://bronevichok.ru/)

Distributed under the ISC License.
