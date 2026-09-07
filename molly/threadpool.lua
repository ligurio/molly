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
    thread_lib.scheduler()

    local first_err
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
    for thread_id = 1, self.thread_num do
        log.debug('Spawn a new thread %d', thread_id)
        local ok = self.pool[thread_id]:create(func, opts)
        if not ok then
            error('Failed to start thread')
        end
    end

    local ok, err = self:join()
    if not ok then
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
