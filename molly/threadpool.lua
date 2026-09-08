-- A thread pool used to execute functions in parallel.
-- Spawns a specified number of worker threads and replenishes the pool if any
-- worker threads panic.

local log = require('molly.log')

local dev_checks = require('molly.dev_checks')
local thread_lib = require('molly.thread')

local function join(self)
    dev_checks('<threadpool>')

    -- Drive coroutine threads to completion first, so their join()
    -- below can observe the result. A no-op for fiber threads, which
    -- are scheduled and joined by the runtime.
    local first_err = nil
    local scheduler_ok, scheduler_err = thread_lib.scheduler()
    if not scheduler_ok then
        first_err = scheduler_err
    end

    for i = 1, self.thread_num do
        local ok, err = self.pool[i]:join()
        if not ok and first_err == nil then
            first_err = err
        end
    end

    if first_err == nil then
        return true
    end
    return false, first_err
end

local function cancel(self)
    dev_checks('<threadpool>')

    for i = 1, self.thread_num do
        self.pool[i]:cancel()
    end

    return true
end

local function start(self, ...)
    dev_checks('<threadpool>')

    local func, opts = ...
    -- Cancel every worker in the pool except a failed one. A failed worker
    -- runs in its own fiber, so killing the rest of the pool from there
    -- releases workers that wait on synchronization primitives.
    local function abort_workers(failed_id)
        for i = 1, self.thread_num do
            if i ~= failed_id then
                self.pool[i]:cancel()
            end
        end
    end

    -- Wrap a worker function to implement a fail-stop behaviour: when a
    -- worker fails, the rest of the pool is cancelled and the first failure
    -- is reported to a caller.
    local function fiber_worker(thread_id)
        local res = {pcall(func, thread_id, opts)}
        if res[1] == false then
            self.failure = self.failure ~= nil and self.failure or
                           tostring(res[2])
            abort_workers(thread_id)
            return false, res[2]
        end
        if res[2] == false then
            local err = res[3]
            self.failure = self.failure ~= nil and self.failure or
                           (err ~= nil and tostring(err) or
                            'worker returned an error')
            abort_workers(thread_id)
        end
        return unpack(res, 2)
    end

    for thread_id = 1, self.thread_num do
        if self.failure ~= nil then
            break
        end
        log.debug('Spawn a new thread %d', thread_id)
        local thread_func = self.thread_type == 'fiber' and
                            fiber_worker or func
        local ok = self.pool[thread_id]:create(thread_func, opts)
        if not ok then
            error('Failed to start thread')
        end
    end

    local ok, err = self:join()
    if not ok and err ~= nil then
        if self.failure ~= nil then
            err = self.failure
        end
        return nil, err
    end

    return true
end

local mt = {
    __type = '<threadpool>',
    __index = {
        start = start,
        cancel = cancel,
        join = join,
    },
}

local function new(thread_type, thread_num)
    dev_checks('string', 'number')

    -- Raises an error when a thread library is not available, e.g.
    -- 'fiber' under LuaJIT.
    thread_lib.set_type(thread_type)

    local pool = {}
    for thread_id = 1, thread_num do
        pool[thread_id] = thread_lib.new(thread_id)
    end

    return setmetatable({
        pool = pool,
        thread_num = thread_num,
        thread_type = thread_type,
    }, mt)
end

return {
    new = new,
}
