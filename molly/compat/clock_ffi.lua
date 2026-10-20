local ffi = require('ffi')
local math = require('math')

ffi.cdef[[
typedef long time_t;
typedef int clockid_t;

typedef struct timespec {
    time_t   tv_sec;        /* seconds */
    long     tv_nsec;       /* nanoseconds */
} ts;

int clock_gettime(clockid_t clk_id, struct timespec *tp);

int clock_nanosleep(clockid_t clock_id, int flags,
                    const struct timespec *rqtp,
                    struct timespec *rmtp);
]]

local clock = {}

-- A single scratch timespec reused by all clock functions. Calls
-- do not yield, so there is no reentrancy between sampler calls.
---@type any
local ts = ffi.new("ts[?]", 1)

-- The IDs of the various system clocks (for POSIX.1b interval
-- timers).
local CLOCK_REALTIME = 0
local CLOCK_MONOTONIC = 1
local CLOCK_PROCESS_CPUTIME_ID = 2

function clock.sleep(time)
    ts[0].tv_sec = math.floor(time)
    ts[0].tv_nsec = math.floor((time % 1) * 10^9)
    ffi.C.clock_nanosleep(1, 0, ts, nil)
end

function clock.monotonic()
    ffi.C.clock_gettime(CLOCK_MONOTONIC, ts)
    return assert(tonumber(ts[0].tv_sec)) +
        assert(tonumber(ts[0].tv_nsec)) / 10^9
end

function clock.realtime()
    assert(ffi.C.clock_gettime(CLOCK_REALTIME, ts) == 0)
    return assert(tonumber(ts[0].tv_sec)) +
        assert(tonumber(ts[0].tv_nsec)) / 10^9
end

function clock.monotonic64()
    ffi.C.clock_gettime(CLOCK_MONOTONIC, ts)
    return assert(tonumber(ts[0].tv_sec * 10^9 + ts[0].tv_nsec))
end

function clock.proc()
    ffi.C.clock_gettime(CLOCK_PROCESS_CPUTIME_ID, ts)
    return assert(tonumber(ts[0].tv_sec)) +
        assert(tonumber(ts[0].tv_nsec)) / 10^9
end

return clock
