-- Module with helpers to use with clocks, time and date.
-- @module molly.clock

local is_tarantool = require('molly.utils').is_tarantool

local clock = {}

if is_tarantool() then
    local clock_lib = require('clock')
    clock.monotonic64 = clock_lib.monotonic64
    clock.monotonic = clock_lib.monotonic
    clock.proc = clock_lib.proc
    clock.sleep = require('fiber').sleep
else
    clock = require('molly.compat.clock_ffi')
end

-- Sleep for the specified number of seconds. `clock.sleep` works as
-- `fiber.sleep` when Tarantool is used, because with fibers it additionally
-- yields control to the scheduler, see
-- [Tarantool documentation](https://www.tarantool.io/en/doc/latest/reference/reference_lua/fiber/#fiber-sleep).
-- @number time Number of seconds to sleep.
-- @return nil
--
-- @function sleep

-- The processor time. Derived from C function
-- `clock_gettime(CLOCK_PROCESS_CPUTIME_ID)`. This is the best function to use
-- with benchmarks that need to calculate how much time has been spent within a
-- CPU.
-- @return number, seconds or nanoseconds since processor start.
-- @usage
-- -- This will print nanoseconds in the CPU since the start.
-- > local clock = require('molly.clock')
-- > print(clock.proc())
-- 0.062237105
--
-- @function proc

-- The monotonic time. Derived from C function `clock_gettime(CLOCK_MONOTONIC)`.
-- Monotonic time is similar to wall clock time but is not affected by changes
-- to or from daylight saving time, or by changes done by a user. This is the
-- best function to use with benchmarks that need to calculate elapsed time.
-- @return number, seconds or nanoseconds since the last time that the computer was booted.
-- @usage
-- > local clock = require('molly.clock')
-- > print(clock.monotonic())
-- 92096.202142013
--
-- @function monotonic

-- The monotonic time. Derived from C function `clock_gettime(CLOCK_MONOTONIC)`.
-- Monotonic time is similar to wall clock time but is not affected by changes
-- to or from daylight saving time, or by changes done by a user. This is the
-- best function to use with benchmarks that need to calculate elapsed time.
-- @return seconds or nanoseconds since the last time that the computer was booted.
-- @usage
-- > local clock = require('molly.clock')
-- > print(clock.monotonic64())
-- 60112772175711
--
-- @function monotonic64

-- Get datetime with milliseconds.
-- @return string, string with datetime with milliseconds precision.
-- @usage
-- > local clock = require('molly.clock')
-- > print(clock.dt())
-- 2022-06-01 10:38:07:081899
--
-- @function dt
function clock.dt()
    local ms = string.match(tostring(os.clock()), '%d%.(%d+)')
    local dt = os.date('*t')
    return ('%d-%.2d-%.2d %.2d:%.2d:%.2d:%-6d'):format(dt.year,
                                           dt.month,
                                           dt.day,
                                           dt.hour,
                                           dt.min,
                                           dt.sec,
                                           ms)
end

return clock
