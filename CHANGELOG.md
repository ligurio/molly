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
- Synchronization primitives (a barrier, a mutex and a wait group)
  shared by fiber- and coroutine-based threads.
- Synchronization of client threads at stage boundaries: all
  threads open connections and set up the DB before any of them
  runs operations, and no thread tears down until every thread
  finished operations.
- An optional `reusable` client method that reports whether a
  client survives a crashed invocation without a restart.
- A public `history:is_well_formed()` method that validates an
  operation history against the structure and semantics from the
  Jepsen history documentation.
- `run_test` validates the collected history with
  `history:is_well_formed()` and fails with an error when the
  history is not well-formed.

### Changed

- Bump luacheck version.
- Static analysis with `emmylua_check` is run in CI and all reported
  errors are fixed.
- Allow chaining `luafun` iterators with iterators defined in Molly and vice versa.
- Using of SQL prepared statements in test examples.
- Generated operation can be any callable Lua object.
- RW-register generator emits every number only once.

### Removed

- The redundant `fiber` and `coroutine` fields of the `molly.thread`
  module (a backend is selected with `set_type()`).

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
- A failed worker cancels the rest of a thread pool instead of
  leaving other workers hanging on synchronization primitives
  (fail-stop). A failed client stage raises an error, so a single
  failed client aborts the rest of the pool instead of leaving
  threads hanging on a barrier.
- A crashed `invoke` is recorded in a history as an `info`
  operation (an indeterminate state) instead of a `fail`, and
  restarts a process with a new process identifier, as in Jepsen.
  A non-reusable client is reopened before the next operation and
  a failed reconnect is recorded as a `fail` operation.
- An `info` operation counts as a completed operation.
- Worker errors and `false` results returned by `open`, `setup`,
  `teardown` and `close` are propagated from a thread pool to
  `run_test()`.
- Generated operations are invoked exactly once: a shared
  generator cursor is no longer reset by every client thread.
- The `time_limit` option is applied to a workload generator in
  `run_test()`.
- A dev checker `workload_opts` checks a type of `checker`, not
  of `generator`.
- `json.NULL` is available on LuaJIT too (exposed as an alias of
  `cjson.null`).
- A test duration and RPS in a summary are based on monotonic
  (real) time instead of CPU time; requests per second are not
  computed when the elapsed time is zero.
- A client records a private top-level copy of a generated
  operation and of a completion returned by a client, so
  generators and clients that reuse an operation table (for
  example `gen.duplicate`) do not overwrite already recorded
  history entries. Nested values are still shared.

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
