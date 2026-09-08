---- Module with implementation of threads based on fibers.
-- @module molly.thread_fiber
--
-- Fibers are a unique Tarantool feature - 'green' threads or coroutines that
-- run independently of operating system threads. Fibers nicely illustrate
-- Tarantool's theoretical grounding in the actor model, which is based on the
-- concept of a number of light processes that cooperatively multitask and
-- communicate with one another through messaging. An advantageous feature of
-- Tarantool fibers is that they include local storage.
--
-- Tarantool is programmed using Lua, which has its own coroutines, but due to
-- the way that fibers interface with Tarantool's asynchronous event loop, it is
-- better to use fibers rather than Lua coroutines. Fibers work well with all of
-- the non-blocking I/O that is built into Tarantool's application server and
-- fibers yield implicitly to other fibers, whereas this logic would have to be
-- added for coroutines.
--
-- The module provides a thread object (`new`, `create`, `cancel`, `join` and
-- `yield` methods). Thread synchronization primitives are exported by
-- `molly.thread`, see `molly.thread_sync`.
--
--### References
--
-- - [Tarantool Documentation: Module fiber](https://www.tarantool.io/en/doc/latest/reference/reference_lua/fiber/)
-- - [Tarantool Documentation: Transaction Control](https://www.tarantool.io/en/doc/latest/book/box/atomic/)
-- - [Tarantool Internals: Fibers](https://docs.tarantool.dev/en/latest/fiber.html)
-- - [Separate roles of fibers that do network I/O and execute
-- requests](https://blueprints.launchpad.net/tarantool/+spec/fiber-specialization)
-- - [When to use fibers and when to use co-routines in
-- Tarantool?](https://stackoverflow.com/questions/36152489/when-to-use-fibers-and-when-to-use-co-routines-in-tarantool)
--
-- @see molly.thread_sync
-- @see molly.thread_coroutine

local has_fiber, fiber = pcall(require, 'fiber')
if not has_fiber then
    return nil
end

local dev_checks = require('molly.dev_checks')

local function create(self, ...)
    dev_checks('<thread>')

    local func, opts = ...
    local fiber_obj = fiber.new(func, self.thread_id, opts)
    if fiber_obj:status() ~= 'dead' then
        fiber_obj:set_joinable(true)
        fiber_obj:name(('thread id %d'):format(self.thread_id))
        fiber_obj:wakeup() -- Needed for backward compatibility with 1.7.
        rawset(self, 'fiber_obj', fiber_obj)
    end

    return true
end

-- TODO: should be a module function (fiber.yield()).
local function yield()
    fiber.yield()
    return true
end

local function cancel(self)
    dev_checks('<thread>')

    local fiber_obj = self.fiber_obj
    if fiber_obj ~= nil and fiber_obj:status() ~= 'dead' then
        if type(fiber_obj.cancel) == 'function' then
            fiber_obj:cancel()
        elseif type(fiber_obj.kill) == 'function' then
            fiber_obj:kill()
        else
            error('a fiber object has no cancel method')
        end
    end

    return true
end

local function join(self)
    dev_checks('<thread>')

    if self.fiber_obj == nil then
        return true
    end

    local vals = { self.fiber_obj:join() }
    if vals[1] == false then
        -- A fiber has terminated with an error.
        return false, tostring(vals[2])
    end
    if vals[2] == false then
        -- A worker returned (false, err).
        local err = vals[3]
        return false, err ~= nil and tostring(err) or 'worker returned an error'
    end

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
}
