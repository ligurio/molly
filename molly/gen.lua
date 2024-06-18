---- Module with functions for generators.
-- @module molly.gen
--
-- One of the key pieces of a Molly test is a generators for client and
-- nemesis operations. These generators will create a finite or infinite
-- sequence of operations. It is often test have its own nemesis generator, but
-- most likely shares a common client generator with other tests. A nemesis
-- generator, for instance, might be a sequence of partition, sleep, and
-- restore, repeated infinitely. A client generator will specify a random,
-- infinite sequence of client operation, as well as the associated parameters
-- such as durability level, the document key, the new value to write or CAS
-- (Compare-And-Set), etc. When a test starts, the client generator feeds
-- client operations to the client and the nemesis generator feeds operations
-- to the nemesis. The test will continue until either the nemesis generator
-- has completed a specified number of operations, a time limit is reached, or
-- an error is thrown.
--
-- Example of generator that generates two operations `w` and `r`:
--
--    local w = function() return { f = 'w', v = math.random(1, 10) } end
--    local r = function() return { f = 'r', v = nil } end
--    gen.rands(0, 2):map(function(x)
--                            return (x == 0 and r()) or
--                                   (x == 1 and w()))
--                        end):take(100)
--
--    local w = function(x) return { f = 'w', v = x } end
--    gen.map(w, gen.rands(1, 10):take(50))
--
--### References:
--
-- - [Lua Functional Library documentation](https://luafun.github.io/)
-- - [Lua Functional Library documentation: Under the Hood](https://luafun.github.io/under_the_hood.html)
-- - [Lua iterators tutorial](http://lua-users.org/wiki/IteratorsTutorial)
-- - [Jepsen generators in a nutshell](http://jepsen-io.github.io/jepsen/jepsen.generator.html)
--
-- @see molly.op

local fun = require('fun')
local clock = require('molly.clock')
local tbl = require('molly.compat.tbl')

local fun_mt = debug.getmetatable(fun.range(10))
local methods = fun_mt.__index
local exports = tbl.copy(fun)

local unwrap = function(self)
    return self.gen, self.param, self.state
end

-- Helpers

local nil_gen = function(_param, _state) -- luacheck: no unused
    return nil
end

--- Basic Functions
-- @section

--- Make an iterator from the iterable object.
-- See [fun.iter](https://luafun.github.io/basic.html#fun.iter).
--
-- @param object - an iterable object (map, array, string).
-- @return an iterator
-- @usage
-- > for _it, v in gen.iter({1, 2, 3}) do print(v) end
-- 1
-- 2
-- 3
-- ---
-- ...
--
-- > for _it, v in gen.iter({a = 1, b = 2, c = 3}) do print(v) end
-- b
-- a
-- c
-- ---
-- ...
--
-- > for _it, v in gen.iter("abc") do print(v) end
-- a
-- b
-- c
-- ---
-- ...
--
--- @function iter

--- Execute the function `fun` for each iteration value.
-- See [fun.each](https://luafun.github.io/basic.html#fun.each).
-- @param function
-- @param iterator - an iterator or iterable object
-- @return none
-- @usage
--
-- > gen.each(print, { a = 1, b = 2, c = 3})
-- b       2
-- a       1
-- c       3
-- ---
-- ...
--
-- @function each

--- An alias for each().
-- See `gen.each`.
-- @function for_each

--- An alias for each().
-- See `gen.each`.
-- @function foreach

--- Generators: Finite Generators
-- @section

--- The iterator to create arithmetic progressions.
-- Iteration values are generated within closed interval `[start, stop]` (i.e.
-- `stop` is included). If the `start` argument is omitted, it defaults to 1 (`stop
-- > 0`) or to -1 (`stop < 0`). If the `step` argument is omitted, it defaults to 1
-- (`start <= stop`) or to -1 (`start > stop`). If `step` is positive, the last
-- element is the largest `start + i * step` less than or equal to `stop`; if `step`
-- is negative, the last element is the smallest `start + i * step` greater than
-- or equal to `stop`. `step` must not be zero (or else an error is raised).
-- `range(0)` returns empty iterator.
-- See [fun.range](https://luafun.github.io/generators.html#fun.range).
--
-- @number[opt] start – an endpoint of the interval.
-- @number stop – an endpoint of the interval.
-- @number[opt] step – a step.
-- @return an iterator
--
-- @usage
-- > for _it, v in gen.range(1, 6) do print(v) end
-- 1
-- 2
-- 3
-- 4
-- 5
-- 6
-- ---
-- ...
--
-- > for _it, v in gen.range(1, 6, 2) do print(v) end
-- 1
-- 3
-- 5
-- ---
-- ...
--
-- @function range

--- Generators: Infinity Generators
-- @section

--- The iterator returns values over and over again indefinitely. All values
-- that passed to the iterator are returned as-is during the iteration.
-- See [fun.duplicate](https://luafun.github.io/generators.html#fun.duplicate).
--
-- @usage
-- > gen.each(print, gen.take(3, gen.duplicate('a', 'b', 'c')))
-- a       b       c
-- a       b       c
-- a       b       c
-- ---
-- ...
--
-- @function duplicate

--- An alias for duplicate().
-- @function xrepeat
-- See `gen.duplicate`.

--- An alias for duplicate().
-- @function replicate
-- See `gen.duplicate`.

--- Return `fun(0)`, `fun(1)`, `fun(2)`, ... values indefinitely.
-- @function tabulate
-- See [fun.tabulate](https://luafun.github.io/generators.html#fun.tabulate).

--- Generators: Random sampling
-- @section

--- @function rands
-- See [fun.rands](https://luafun.github.io/generators.html#fun.rands).

--- Slicing: Subsequences
-- @section

--- @function take_n
-- See [fun.take_n](https://luafun.github.io/slicing.html#fun.take_n).

--- @function take_while
-- See [fun.take_while](https://luafun.github.io/slicing.html#fun.take_while).

--- @function take
-- See [fun.take](https://luafun.github.io/slicing.html#fun.take).

--- @function drop_n
-- See [fun.drop_n](https://luafun.github.io/slicing.html#fun.drop_n).

--- @function drop_while
-- See [fun.drop_while](https://luafun.github.io/slicing.html#fun.drop_while).

--- @function drop
-- See [fun.drop](https://luafun.github.io/slicing.html#fun.drop).

--- @function span
-- See [fun.span](https://luafun.github.io/slicing.html#fun.span).
local span = fun.span
methods.span = span
exports.span = span
--- An alias for span().
-- See `fun.span`.
-- @function split

--- An alias for span().
-- See `fun.span`.
-- @function split_at

--- Indexing
-- @section

--- @function index
-- See [fun.index](https://luafun.github.io/indexing.html#fun.index).

--- An alias for index().
-- See `fun.index`.
-- @function index_of

--- An alias for index().
-- See `fun.index`.
-- @function elem_index

--- @function indexes
-- See [fun.indexes](https://luafun.github.io/indexing.html#fun.indexes).

--- An alias for indexes().
-- See `fun.indexes`.
-- @function indices

--- An alias for indexes().
-- See `fun.indexes`.
-- @function elem_indexes

--- An alias for indexes().
-- See `fun.indexes`.
-- @function elem_indices

--- Filtering
-- @section

--- Return a new iterator of those elements that satisfy the `predicate`.
-- See [fun.filter](https://luafun.github.io/filtering.html#fun.filter).
-- @function filter

--- An alias for filter().
-- See `gen.filter`.
-- @function remove_if

--- If `regexp_or_predicate` is string then the parameter is used as a regular
-- expression to build filtering predicate. Otherwise the function is just an
-- alias for gen.filter().
-- @function grep
-- See [fun.grep](https://luafun.github.io/filtering.html#fun.grep).

--- The function returns two iterators where elements do and do not satisfy the
-- predicate.
-- @function partition
-- See [fun.partition](https://luafun.github.io/filtering.html#fun.partition).

--- Reducing: Folds
-- @section

--- The function reduces the iterator from left to right using the binary
-- operator `accfun` and the initial value `initval`.
-- @function foldl
-- See [fun.foldl](https://luafun.github.io/reducing.html#fun.foldl).

--- An alias to foldl().
-- See `gen.foldl`.
-- @function reduce

--- Return a number of elements in `gen, param, state` iterator.
-- @function length
-- See [fun.length](https://luafun.github.io/reducing.html#fun.length).

--- Return a new table (array) from iterated values.
-- @function totable
-- See [fun.totable](https://luafun.github.io/reducing.html#fun.totable).

--- Return a new table (map) from iterated values.
-- @function tomap
-- See [fun.tomap](https://luafun.github.io/reducing.html#fun.tomap).

--- Reducing: Predicates
-- @section

--- @function is_prefix_of
-- See [fun.is_prefix_of](https://luafun.github.io/reducing.html#fun.is_prefix_of).

--- @function is_null
-- See [fun.is_null](https://luafun.github.io/reducing.html#fun.is_null).

--- @function all
-- See [fun.all](https://luafun.github.io/reducing.html#fun.all).

--- An alias for all().
-- See `fun.all`.
-- @function every

--- @function any
-- See [fun.any](https://luafun.github.io/reducing.html#fun.any).

--- An alias for any().
-- See `fun.any`.
-- @function some

--- Transformations
-- @section

--- @function map
-- See [fun.map](https://luafun.github.io/transformations.html#fun.map).

--- @function enumerate
-- See [fun.enumerate](https://luafun.github.io/transformations.html#fun.enumerate).

--- @function intersperse
-- See [fun.intersperse](https://luafun.github.io/transformations.html#fun.intersperse).

--- Compositions
-- @section

--- Return a new iterator where i-th return value contains the i-th element
-- from each of the iterators. The returned iterator is truncated in length to
-- the length of the shortest iterator. For multi-return iterators only the
-- first variable is used.
-- See [fun.zip](https://luafun.github.io/compositions.html#fun.zip).
-- @param ... - an iterators
-- @return an iterator
-- @function zip

--- A cycled version of an iterator.
-- Make a new iterator that returns elements from `{gen, param, state}` iterator
-- until the end and then "restart" iteration using a saved clone of `{gen,
-- param, state}`. The returned iterator is constant space and no return values
-- are buffered. Instead of that the function make a clone of the source `{gen,
-- param, state}` iterator. Therefore, the source iterator must be pure
-- functional to make an indentical clone. Infinity iterators are supported,
-- but are not recommended.
-- @param iterator - an iterator
-- @return an iterator
-- See [fun.cycle](https://luafun.github.io/compositions.html#fun.cycle).
-- @function cycle

--- Make an iterator that returns elements from the first iterator until it is
-- exhausted, then proceeds to the next iterator, until all of the iterators are
-- exhausted. Used for treating consecutive iterators as a single iterator.
-- Infinity iterators are supported, but are not recommended.
-- See [fun.chain](https://luafun.github.io/compositions.html#fun.chain).
-- @param ... - an iterators
-- @return an iterator, a consecutive iterator from sources (left from right).
-- @usage
-- > fun.each(print, fun.chain(fun.range(5, 1, -1), fun.range(1, 5)))
-- 5
-- 4
-- 3
-- 2
-- 1
-- 1
-- 2
-- 3
-- 4
-- 5
-- ---
-- ...
--
-- @function chain

--- (TODO) Cycles between several generators on a rotating schedule.
-- Takes a flat series of [time, generator] pairs.
-- @param ... - an iterators
-- @return an iterator
-- @function cycle_times
local cycle_times = function()
    -- TODO
end
methods.cycle_times = cycle_times

local mix_gen

mix_gen = function(_, state)
    assert(type(state) == 'table')
    local len = table.getn(state)
    if len == 0 then
        return nil, nil
    end
    local nth = math.random(len)
    local it = state[nth]
    local gen1, param1, state1 = unwrap(it)
    local state2, value = gen1(param1, state1)
    if value == nil then
        table.remove(state, nth)
        return mix_gen(nil, state)
    end
    state[nth] = fun.wrap(gen1, param1, state2)
    return state, value
end

--- A random mixture of a number generators. Takes a collection of
-- generators and chooses between them uniformly.
--
-- @usage
-- > molly.gen.range(1, 5):mix(molly.gen.range(5, 10)):totable()
-- ---
-- - - 1
--   - 5
--   - 2
--   - 3
--   - 6
--   - 7
--   - 4
--   - 8
--   - 9
--   - 5
--   - 10
--
-- @param ... - an iterators
-- @return an iterator
-- @function mix
local function mix(...)
    local params = {...}
    local state = {}
    for _, it in ipairs(params) do
        if tostring(it) == '<generator>' then
            table.insert(state, it)
        end
    end
    return fun.wrap(mix_gen, nil, state)
end
methods.mix = mix
exports.mix = mix

--- (TODO) Emits an operation from generator A, then B, then A again, then B again,
-- etc. Stops as soon as any gen is exhausted.
-- @number a generator A.
-- @number b generator B.
-- @return an iterator
--
-- @function flip_flop
local flip_flop = (function()
    -- TODO
end)
methods.flip_flop = flip_flop

--- Special generators
-- @section

--- (TODO) A generator which, when asked for an operation, logs a message and yields
--  nil. Occurs only once; use `repeat` to repeat.
-- @return an iterator
--
-- @function log
local log = function()
    -- TODO
end
exports.log = log

--- (TODO) Operations from that generator are scheduled at uniformly random intervals
-- between `0` to `2 * (dt seconds)`.
-- @number dt Number of seconds.
-- @return an iterator
--
-- @function stagger
local stagger = (function()
    -- TODO
end)
methods.stagger = stagger

--- Stops generating items when time limit is exceeded.
-- @number duration Number of seconds.
-- @return an iterator
--
-- @usage
-- >  for _it, v in gen.time_limit(gen.range(1, 100), 0.0001) do print(v) end
-- 1
-- 2
-- 3
-- 4
-- 5
-- 6
-- 7
-- 8
-- 9
-- 10
-- 11
-- 12
-- ---
-- ...
--
-- @function time_limit
local time_limit = (function(fn)
    return function(self, arg1)
        return fn(arg1, self.gen, self.param, self.state)
    end
end)(function(timeout, gen, param, state)
    if type(timeout) ~= 'number' or timeout == 0 then
        error("bad argument with duration to time_limit", 2)
    end
    local get_time = clock.monotonic
    local start_time = get_time()
    local time_is_exceed = false
    return fun.wrap(function(ctx, state_x)
        local gen_x, param_x, duration, cnt = ctx[1], ctx[2], ctx[3], ctx[4] + 1
        ctx[4] = cnt
        if time_is_exceed == false then
            time_is_exceed = get_time() - start_time >= duration
            return gen_x(param_x, state_x)
        end
        return nil_gen(nil, nil)
    end, {gen, param, timeout, 0}, state)
end)
methods.time_limit = time_limit
exports.time_limit = time_limit

return exports
