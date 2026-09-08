---- Module with thread implementation.
-- @module molly.thread
--
-- The module stores an active thread type and delegates generic
-- thread operations (`new`, `yield`, `scheduler`) and
-- synchronization primitives to the corresponding implementation:
--
-- - `molly.compat.thread_fiber` - threads, based on Tarantool
--   fibers.
-- - `molly.compat.thread_coroutine` - threads, based on Lua
--   coroutines.
--
-- This is the single entry point for thread synchronization
-- primitives: a barrier, a mutex and a wait group. All of them
-- are bound to the active thread backend through `yield`, so they
-- behave identically for fibers and coroutines.
--
-- All primitives are designed for a cooperative environment:
-- a thread that cannot proceed yet yields control to a scheduler
-- instead of blocking an OS thread. Semantics follow well-known
-- counterparts from other languages:
--
--  - a barrier resembles `pthread_barrier_wait` from POSIX
--  threads;
--  - a mutex resembles `sync.Mutex` from Go;
--  - a wait group resembles `sync.WaitGroup` from Go.
--
-- Primitives are plain shared objects and are not tied to the
-- lifetime of a thread that created or uses them.
--
-- A barrier releases a group of threads once every thread reaches
-- it:
--
--```lua
-- local thread = require('molly.thread')
-- -- 'coroutine' is used by default.
-- thread.set_type('fiber')
-- local n = 3
-- local barrier = thread.barrier_new(n)
--
-- local function worker(thread_id, opts)
--     -- Wait until every thread has finished the first stage.
--     barrier:wait()
--     -- ... run the second stage ...
-- end
--```
--
-- A mutex serializes access to shared data and a wait group waits
-- until all threads are done:
--
--```lua
-- local mutex = thread.mutex_new()
-- mutex:lock()
-- -- ... protected shared data ...
-- mutex:unlock()
--
-- local wg = thread.wg_new()
-- wg:add(n)
-- -- ... each thread calls wg:done() ...
-- wg:wait()
--```
--
-- @see molly.thread_fiber
-- @see molly.thread_coroutine

local dev_checks = require('molly.dev_checks')

local thread_coroutine = require('molly.compat.thread_coroutine')
local thread_fiber = require('molly.compat.thread_fiber')
local thread_sync = require('molly.thread_sync')

-- A module that returns nil (e.g. `thread_fiber` when fibers are
-- unavailable) is loaded by `require` as `true`, so keep only
-- usable implementations in the map.
local thread = {}
if type(thread_fiber) == 'table' then
    thread['fiber'] = thread_fiber
end
if type(thread_coroutine) == 'table' then
    thread['coroutine'] = thread_coroutine
end

local current = thread_coroutine

--- Set an active thread type. Raises an error for an unknown type
-- or for a type with no implementation in the current runtime,
-- e.g. 'fiber' under LuaJIT.
-- @string thread_type Thread type: 'fiber' or 'coroutine'.
-- @return an active thread implementation
local function set_type(thread_type)
    dev_checks('string')

    local implementation = thread[thread_type]
    if implementation == nil then
        error(('No thread library with type "%s"'):format(thread_type))
    end
    current = implementation
    return current
end

--- Create a new thread of the active type.
-- @number thread_id A thread identifier.
-- @return a thread object
local function new(thread_id)
    dev_checks('number')

    return current.new(thread_id)
end

--- Yield control to a scheduler of the active thread type.
-- @return true
---@async
local function yield()
    return current.yield()
end

--- Drive coroutine threads to completion. A no-op for fiber
-- threads, which are scheduled by the runtime.
local function scheduler()
    if current.scheduler ~= nil then
        return current.scheduler()
    end
    return true
end

-- Synchronization primitives are created once with a `yield` that
-- dispatches to the active thread backend, so the same primitives
-- work for both fibers and coroutines.

--- Create a barrier that releases a group of `n` threads. A
-- barrier is reusable: when the last thread arrives, all threads
-- are released and the barrier starts to count a next round.
--
-- A barrier has a single method, `wait()`, that blocks the
-- calling thread until all `n` threads arrive at the barrier.
--
-- @number n A number of threads.
-- @return barrier
-- @function barrier_new
local barrier_new = thread_sync.make_barrier(yield)

--- Create an unlocked mutex.
--
-- A mutex has the following methods:
--
-- - **lock()** - acquire the mutex, yielding until it becomes
-- available;
-- - **unlock()** - release the mutex, an error to unlock an
-- unlocked mutex;
-- - **trylock()** - try to acquire the mutex without blocking and
-- report whether it succeeded.
--
-- A mutex does not track its owner: any thread may call
-- `unlock()`. If a thread is terminated while holding a mutex,
-- the mutex stays locked and `lock()` yields forever, so use a
-- non-blocking `trylock()` to detect such a state.
--
-- @return mutex
-- @function mutex_new
local mutex_new = thread_sync.make_mutex(yield)

--- Create a wait group with a zero counter.
--
-- A wait group has the following methods:
--
-- - **add(delta)** - add `delta`, which may be negative, to the
-- counter;
-- - **done()** - decrement the counter by one;
-- - **wait()** - block until the counter is zero.
--
-- @return wg
-- @function wg_new
local wg_new = thread_sync.make_wg(yield)

return {
    set_type = set_type,
    new = new,
    yield = yield,
    scheduler = scheduler,
    ['fiber'] = thread['fiber'],
    ['coroutine'] = thread['coroutine'],

    -- Synchronization primitives.
    barrier_new = barrier_new,
    mutex_new = mutex_new,
    wg_new = wg_new,
}
