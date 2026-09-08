---- Module with implementation of threads based on coroutines.
-- @module molly.thread_coroutine
--
--### References
--
-- - [Programming in Lua, Coroutines](http://www.lua.org/pil/9.html) -
-- Roberto Ierusalimschy
-- - [Coroutines in Lua](https://www.lua.org/doc/jucs04.pdf) - Ana L´ucia de
-- Moura, Noemi Rodriguez, Roberto Ierusalimschy
--
-- The module provides a thread object (`new`, `create`, `cancel`, `join` and
-- `yield` methods) and a scheduler that runs registered threads. Thread
-- synchronization primitives are exported by `molly.thread`, see
-- `molly.thread_sync`.
--
-- @see molly.thread_sync
-- @see molly.thread_fiber

local math = require('math')

local dev_checks = require('molly.dev_checks')

local threads = {}

local function scheduler()
    while true do
        local n = table.getn(threads)
        if n == 0 then break end   -- No more threads to run.
        local id = math.random(1, n)
        local thread = threads[id]
        local co = thread['coro']
        if coroutine.status(co) == 'suspended' then
            local res
            if thread['started'] == true then
                res = {coroutine.resume(co)}
            else
                thread['started'] = true
                res = {coroutine.resume(co, thread.thread_id,
                                       unpack(thread['func_args']))}
            end
            thread['last_result'] = res
        end
        if coroutine.status(co) == 'dead' then
            table.remove(threads, id)
        end
    end
    return true
end

local function create(self, ...)
    dev_checks('<thread>')

    local params = {...}
    rawset(self, 'coro', coroutine.create(params[1]))
    local func_args = {}
    for i = 2, #params do
        table.insert(func_args, params[i])
    end
    rawset(self, 'func_args', func_args)
    rawset(self, 'started', false)
    table.insert(threads, self)

    return true
end

local function cancel(self)
    dev_checks('<thread>')
    -- TODO
    return true
end

local function join(self)
    dev_checks('<thread>')

    local res = self['last_result']
    if res == nil then
        return true
    end
    if res[1] == false then
        -- A coroutine has terminated with an error.
        return false, tostring(res[2])
    end
    if res[2] == false then
        -- A worker returned (false, err).
        local err = res[3]
        return false, err ~= nil and tostring(err) or 'worker returned an error'
    end

    return true
end

local function yield()
    coroutine.yield()
    return true
end

local mt = {
    __type = '<thread>',
    __index = {
        create = create,
        cancel = cancel,
        join = join,
        yield = yield,
    },
}

local function new(thread_id)
    dev_checks('number')

    return setmetatable({
        thread_id = thread_id,
    }, mt)
end

return {
    new = new,
    yield = yield,
    scheduler = scheduler,
}
