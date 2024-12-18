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
