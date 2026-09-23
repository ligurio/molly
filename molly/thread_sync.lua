-- Internal, backend-independent implementation of thread
-- synchronization primitives: a barrier, a mutex and a wait
-- group. `molly.thread` injects a `yield` function and is the
-- public entry point that documents the primitives.

local dev_checks = require('molly.dev_checks')

local function check_yield(yield)
    if type(yield) ~= 'function' then
        error('yield is not a function')
    end
end

-- Build a barrier constructor bound to a `yield` function.
local function make_barrier(yield)
    check_yield(yield)

    -- Waiting threads poll the generation counter; the last one
    -- to arrive bumps it and releases the current round.
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

    return barrier_new
end

-- Build a mutex constructor bound to a `yield` function.
local function make_mutex(yield)
    check_yield(yield)

    local function mutex_lock(self)
        while self.locked do
            yield()
        end
        self.locked = true
    end

    local function mutex_unlock(self)
        if not self.locked then
            error('mutex is not locked')
        end
        self.locked = false
    end

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

    local function mutex_new()
        local self = {
            locked = false,
        }
        return setmetatable(self, mutex_mt)
    end

    return mutex_new
end

-- Build a wait group constructor bound to a `yield` function.
local function make_wg(yield)
    check_yield(yield)

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

    local function wg_done(self)
        dev_checks('<wg>')
        self:add(-1)
    end

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

    local function wg_new()
        local self = {
            count = 0,
        }
        return setmetatable(self, wg_mt)
    end

    return wg_new
end

return {
    make_barrier = make_barrier,
    make_mutex = make_mutex,
    make_wg = make_wg,
}
