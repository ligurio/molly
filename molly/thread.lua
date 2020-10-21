---- Module with thread implementation.
-- @module molly.thread
--
-- - `jepsen.compat.thread_fiber` - threads, based on Tarantool fibers.
-- - `jepsen.compat.thread_coroutine` - threads, based on Lua coroutines.

local thread_coroutine = require('molly.compat.thread_coroutine')
local thread_fiber = require('molly.compat.thread_fiber')

return {
    ['fiber'] = thread_fiber,
    ['coroutine'] = thread_coroutine,
}
