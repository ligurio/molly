---- Module with thread implementation.
-- @module molly.thread
--
-- The module stores an active thread type and delegates generic thread
-- operations (`new`, `yield`, `scheduler`) to the corresponding
-- implementation:
--
-- - `molly.compat.thread_fiber` - threads, based on Tarantool fibers.
-- - `molly.compat.thread_coroutine` - threads, based on Lua coroutines.

local dev_checks = require('molly.dev_checks')

local thread_coroutine = require('molly.compat.thread_coroutine')
local thread_fiber = require('molly.compat.thread_fiber')

-- A module that returns nil (e.g. `thread_fiber` when fibers are
-- unavailable) is loaded by `require` as `true`, so keep only usable
-- implementations in the map.
local thread = {}
if type(thread_fiber) == 'table' then
    thread['fiber'] = thread_fiber
end
if type(thread_coroutine) == 'table' then
    thread['coroutine'] = thread_coroutine
end

local current = thread_coroutine

--- Set an active thread type. Raises an error for an unknown type or
-- for a type with no implementation in the current runtime, e.g.
-- 'fiber' under LuaJIT.
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
local function yield()
    return current.yield()
end

--- Drive coroutine threads to completion. A no-op for fiber threads,
-- which are scheduled by the runtime.
local function scheduler()
    if current.scheduler ~= nil then
        current.scheduler()
    end
    return true
end

return {
    set_type = set_type,
    new = new,
    yield = yield,
    scheduler = scheduler,
    ['fiber'] = thread['fiber'],
    ['coroutine'] = thread['coroutine'],
}
