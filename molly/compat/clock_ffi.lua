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

-- luacheck: push no unused
-- The IDs of the various system clocks (for POSIX.1b interval timers).
local CLOCK_REALTIME = 0
local CLOCK_MONOTONIC = 1
local CLOCK_PROCESS_CPUTIME_ID = 2
local CLOCK_THREAD_CPUTIME_ID = 3
local CLOCK_MONOTONIC_RAW = 4
local CLOCK_REALTIME_COARSE = 5
local CLOCK_MONOTONIC_COARSE = 6
local CLOCK_BOOTTIME = 7
local CLOCK_REALTIME_ALARM = 8
local CLOCK_BOOTTIME_ALARM = 9
-- luacheck: pop

function clock.sleep(time)
    local ts = assert(ffi.new("ts[?]", 1))
    ts[0].tv_sec = math.floor(time / 1000)
    ts[0].tv_nsec = (time % 1000) * 1000000
    ffi.C.clock_nanosleep(1, 0, ts, nil)
end

function clock.monotonic()
    local ts = assert(ffi.new("ts[?]", 1))
    ffi.C.clock_gettime(CLOCK_MONOTONIC, ts)
    return tonumber(ts[0].tv_sec * 1000 +
           math.floor(tonumber(ts[0].tv_nsec / 1000000)))
end

function clock.monotonic64()
    local ts = assert(ffi.new("ts[?]", 1))
    ffi.C.clock_gettime(CLOCK_MONOTONIC, ts)
    return tonumber(ts[0].tv_sec * 10^9 + ts[0].tv_nsec)
end

function clock.proc()
    local ts = assert(ffi.new("ts[?]", 1))
    ffi.C.clock_gettime(CLOCK_PROCESS_CPUTIME_ID, ts)
    return tonumber(ts[0].tv_sec) + tonumber(ts[0].tv_nsec) / 10^9
end

return clock
