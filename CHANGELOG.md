# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- A `log()` iterator.
- A `mix()` iterator.
- A CAS-register generator.
- A bank generator.
- A `cycle_times()` iterator.
- A `flip_flop()` iterator.

### Changed

- Bump luacheck version.
- Allow chaining `luafun` iterators with iterators defined in Molly and vice versa.
- Using of SQL prepared statements in test examples.
- Generated operation can be any callable Lua object.
- RW-register generator emits every number only once.

### Removed

### Fixed

- Executing `close` method in a `Client` instance (#2).
- list-append generator (#3).
- Passing a client object to a client's methods (#9).
- Links in rendered LDoc documentation for a module `molly.gen`.
- `clock.monotonic()` and `clock.sleep()` use seconds on LuaJIT like on Tarantool.
- `history:to_txt()` builds a history in a linear time.
- A missing checker for the `any` type in `molly.checks`.
- Coroutine-based threads pass a `thread_id` and arguments to
  a worker function.
- A client yields to a scheduler through `molly.thread` according
  to the active thread type (fiber or coroutine).
- A failed `invoke` is recorded in a history as a `fail` operation
  with an error message.
- Worker errors and `false` results returned by `open`, `setup`,
  `teardown` and `close` are propagated from a thread pool to
  `run_test()`.

[Unreleased]: https://github.com/ligurio/molly/compare/0.1.0...HEAD

## 0.1.0

Initial version of a Jepsen-like framework written in Lua programming language.

### Added

- Compatibility with a Jepsen-history format.
- Support of Tarantool fibers.
- Support of Lua coroutines.
- GH Actions workflows with check, testing, publishing actions.
- Luarocks spec.
- Examples with SQLite tests.
- Generators with `list-append` and `rw-register` operations.
