---- Module with implementation of threads based on coroutines.
-- @module molly.thread_coroutine
--
--### References
--
-- - [Programming in Lua, Coroutines](http://www.lua.org/pil/9.html) -
-- Roberto Ierusalimschy
-- - [Coroutines in Lua](https://www.lua.org/doc/jucs04.pdf) - Ana L´ucia de
-- Moura, Noemi Rodriguez, Roberto Ierusalimschy

local math = require('math')

local dev_checks = require('molly.dev_checks')
local utils = require('molly.utils')

local threads = {}

local function scheduler()
    while true do
        local n = table.getn(threads)
        if n == 0 then break end   -- No more threads to run.
        local id = math.random(1, n)
        local thread = threads[id]
        local co = thread['coro']
        local func_args = thread['func_args']
        if coroutine.status(co) == 'suspended' then
            coroutine.resume(co, unpack(func_args))
        end
        if coroutine.status(co) == 'dead' then
            table.remove(threads, id)
        end
    end
end

local function create(self, ...)
    dev_checks('<thread>')

    local fn, func_args = ...
    rawset(self, 'coro', coroutine.create(fn, self.thread_id, utils.pack(func_args)))
    rawset(self, 'func_args', func_args)
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
    -- TODO
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
