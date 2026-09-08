-- Module with helpers to use with clocks, time and date.
-- @module molly.clock

local is_tarantool = require('molly.utils').is_tarantool

local clock = {}

if is_tarantool() then
    local clock_lib = require('clock')
    clock.monotonic64 = clock_lib.monotonic64
    clock.monotonic = clock_lib.monotonic
    clock.proc = clock_lib.proc
    clock.realtime = clock_lib.realtime
    clock.sleep = require('fiber').sleep
else
    clock = require('molly.compat.clock_ffi')
end

-- Sleep for the specified number of seconds. `clock.sleep` works
-- as `fiber.sleep` when Tarantool is used, because with fibers it
-- additionally yields control to the scheduler, see a description
-- for `fiber.sleep(time)` in the Tarantool documentation.
-- @number time Number of seconds to sleep.
-- @return nil
--
-- @function sleep

-- The processor time. Derived from C function
-- `clock_gettime(CLOCK_PROCESS_CPUTIME_ID)`. This is the best
-- function to use with benchmarks that need to calculate how much
-- time has been spent within a CPU.
-- @return number, seconds or nanoseconds since processor start.
-- @usage
-- -- This will print nanoseconds in the CPU since the start.
-- > local clock = require('molly.clock')
-- > print(clock.proc())
-- 0.062237105
--
-- @function proc

-- The monotonic time. Derived from C function
-- `clock_gettime(CLOCK_MONOTONIC)`. Monotonic time is similar to
-- wall clock time but is not affected by changes to or from
-- daylight saving time, or by changes done by a user. This is the
-- best function to use with benchmarks that need to calculate
-- elapsed time.
-- @return number, seconds or nanoseconds since the last time that
-- the computer was booted.
-- @usage
-- > local clock = require('molly.clock')
-- > print(clock.monotonic())
-- 92096.202142013
--
-- @function monotonic

-- The monotonic time. Derived from C function
-- `clock_gettime(CLOCK_MONOTONIC)`. Monotonic time is similar to
-- wall clock time but is not affected by changes to or from
-- daylight saving time, or by changes done by a user. This is the
-- best function to use with benchmarks that need to calculate
-- elapsed time.
-- @return seconds or nanoseconds since the last time that the
-- computer was booted.
-- @usage
-- > local clock = require('molly.clock')
-- > print(clock.monotonic64())
-- 60112772175711
--
-- @function monotonic64

-- The real time. Derived from C function
-- `clock_gettime(CLOCK_REALTIME)`. Real time may be affected by
-- changes done by a user or by a system time synchronization.
-- Best function to use to obtain a current date and time.
-- @return number, seconds since epoch (1970-01-01 00:00:00 UTC).
-- @usage
-- > local clock = require('molly.clock')
-- > print(clock.realtime())
-- 1735689600.5
--
-- @function realtime

-- Get current datetime with a sub-second part.
-- @return string, string with datetime with microsecond
-- precision.
-- @usage
-- > local clock = require('molly.clock')
-- > print(clock.dt())
-- 2025-06-15 18:06:40:081899
--
-- @function dt
function clock.dt()
    local now = clock.realtime()
    local sec = math.floor(now)
    local usec = math.floor((now - sec) * 10^6)
    local d = os.date('*t', sec)
    return ('%d-%.2d-%.2d %.2d:%.2d:%.2d:%06d'):format(
        d.year, d.month, d.day, d.hour, d.min, d.sec, usec)
end

return clock
