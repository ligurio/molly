---- Module with implementations of primitives that synchronize execution
-- of green threads: a barrier, a mutex and a wait group.
-- @module molly.thread_sync
--
-- Both thread backends supported by Molly -- Tarantool fibers (see
-- `molly.thread_fiber`) and Lua coroutines (see `molly.thread_coroutine`) --
-- share a single implementation of the primitives and differ only in a
-- `yield` function passed to `new()`. The `yield` function releases control
-- to a scheduler: `fiber.yield()` for fibers and `coroutine.yield()` for
-- coroutine-based threads. Therefore the primitives behave identically
-- regardless of a thread backend.
--
-- All primitives are designed for a cooperative environment: a thread that
-- cannot proceed yet yields control to a scheduler instead of blocking an OS
-- thread. Semantics follow well-known counterparts from other languages:
--
--  - a barrier resembles `pthread_barrier_wait` from POSIX threads;
--  - a mutex resembles `sync.Mutex` from Go;
--  - a wait group resembles `sync.WaitGroup` from Go.
--
-- Instead of instantiating the module directly, prefer synchronization
-- primitives exported by `molly.thread`.
--
-- @usage
--
-- -- Threads synchronize their execution between two stages with a barrier:
-- local thread = require('molly.thread')
-- thread.set_type('fiber') -- 'coroutine' is used by default
-- local n = 3
-- local barrier = thread.barrier_new(n)
--
-- local function worker(thread_id, opts) -- luacheck: no unused
--     -- Wait until every thread has finished the first stage.
--     barrier:wait()
--     -- ... run the second stage ...
-- end
--
-- A mutex serializes access to shared data and a wait group waits until all
-- threads are done:
--
--     local mutex = thread.mutex_new()
--     mutex:lock()
--     -- ... protected shared data ...
--     mutex:unlock()
--
--     local wg = thread.wg_new()
--     wg:add(n)
--     -- ... each thread calls wg:done() ...
--     wg:wait()
--
-- @see molly.thread_fiber
-- @see molly.thread_coroutine

local dev_checks = require('molly.dev_checks')

-- Build a set of synchronization primitives bound to a `yield` function.
-- The `yield` function must give a control back to a scheduler of green
-- threads so that other threads can proceed.
--
-- @function new
-- @param yield a function that yields execution to a scheduler
-- @return a table with `barrier_new`, `mutex_new` and `wg_new` functions
local function new(yield)
    if type(yield) ~= 'function' then
        error('yield is not a function')
    end

    ------------------------
    -- Barrier
    ------------------------

    -- A barrier for a group of threads means any thread must stop at this
    -- point and cannot proceed until all other threads reach this barrier.
    -- A barrier is reusable: when the last thread arrives, all threads are
    -- released and the barrier starts to count a next round.

    -- Wait until all `n` threads arrive at the barrier. Returns when the
    -- current round is complete, i.e. all participants reached the barrier.
    local function barrier_wait(self)
        local gen = self.gen
        self.count = self.count + 1
        if self.count == self.n then
            self.count = 0
            self.gen = gen + 1
            return
        end
        while self.gen == gen do
            yield()
        end
    end

    local barrier_mt = {
        __type = '<barrier>',
        __index = {
            wait = barrier_wait,
        },
    }

    -- Create a barrier that releases a group of `n` threads.
    local function barrier_new(n)
        if type(n) ~= 'number' or n < 1 then
            error('a number of threads must be a positive number')
        end
        local self = {
            n = n,
            count = 0,
            gen = 0,
        }
        return setmetatable(self, barrier_mt)
    end

    ------------------------
    -- Mutex
    ------------------------

    -- A mutual exclusion primitive useful for protecting shared data.

    -- Lock locks the mutex. If the mutex is already locked, the calling
    -- thread yields until the mutex becomes available.
    local function mutex_lock(self)
        while self.locked do
            yield()
        end
        self.locked = true
    end

    -- Unlock unlocks the mutex. It is an error to unlock an unlocked mutex.
    local function mutex_unlock(self)
        if not self.locked then
            error('mutex is not locked')
        end
        self.locked = false
    end

    -- Trylock tries to lock the mutex and reports whether it succeeded.
    -- A failed call to trylock does not block the calling thread.
    local function mutex_trylock(self)
        if self.locked then
            return false
        end
        self.locked = true
        return true
    end

    local mutex_mt = {
        __type = '<mutex>',
        __index = {
            lock = mutex_lock,
            unlock = mutex_unlock,
            trylock = mutex_trylock,
        },
    }

    -- Create an unlocked mutex.
    local function mutex_new()
        local self = {
            locked = false,
        }
        return setmetatable(self, mutex_mt)
    end

    ------------------------
    -- Wait group
    ------------------------

    -- A wait group waits for a collection of threads to finish. The main
    -- thread calls add to set the number of threads to wait for. Then each
    -- of the threads runs and calls done when finished. At the same time,
    -- wait can be used to block until all threads have finished.

    -- Add adds a delta, which may be negative, to the wait group counter.
    local function wg_add(self, delta)
        dev_checks('<wg>', 'number')
        if delta == 0 then
            return
        end
        if self.count + delta < 0 then
            error('wait group counter is negative')
        end
        self.count = self.count + delta
    end

    -- Done decrements the wait group counter by one.
    local function wg_done(self)
        dev_checks('<wg>')
        self:add(-1)
    end

    -- Wait blocks until the wait group counter is zero.
    local function wg_wait(self)
        dev_checks('<wg>')
        while self.count > 0 do
            yield()
        end
    end

    local wg_mt = {
        __type = '<wg>',
        __index = {
            add = wg_add,
            done = wg_done,
            wait = wg_wait,
        },
    }

    -- Create a wait group with a zero counter.
    local function wg_new()
        local self = {
            count = 0,
        }
        return setmetatable(self, wg_mt)
    end

    return {
        barrier_new = barrier_new,
        mutex_new = mutex_new,
        wg_new = wg_new,
    }
end

return {
    new = new,
}
