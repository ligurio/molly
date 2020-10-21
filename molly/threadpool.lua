-- A thread pool used to execute functions in parallel.
-- Spawns a specified number of worker threads and replenishes the pool if any
-- worker threads panic.

local log = require('molly.log')

local dev_checks = require('molly.dev_checks')
local thread_lib = require('molly.thread')

local THREAD_TYPE

local function join(self)
    dev_checks('<threadpool>')

    for i = 1, self.thread_num do
        self.pool[i]:join()
    end

    if THREAD_TYPE == 'coroutine' then
        thread_lib[THREAD_TYPE].scheduler()
    end

    return true
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
        if THREAD_TYPE == 'fiber' then
            self.pool[thread_id]:yield()
        end
    end

    local ok = self:join()
    if not ok then
        error('Failed to wait completion')
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

    THREAD_TYPE = thread_type
    local thread = thread_lib[thread_type]
    -- TODO: check thread type in runner.lua
    if type(thread) ~= 'table' then
        error(('No thread library with type "%s"'):format(thread_type))
    end

    local pool = {}
    for thread_id = 1, thread_num do
        pool[thread_id] = thread.new(thread_id)
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
