---- Module with main functions that runs tests.
-- @module molly.runner
--
--### Design Overview
--
-- A Molly test runs as a Lua program on a control node. That program may use
-- remote access to log into a bunch of DB nodes, where it sets up the
-- distributed system you're going to test or use local DB instances.
--
--```
--             +-------------+
--    +------- | controller  | -------+
--    |        +-------------+        |
--    |          |    |    |          |
--    |     +----+    |    |          |
--    v     v         |    |          v
--  +----+----+----+  |    |  +----+----+
--  | n1 | n2 | n3 | <+    +> | n4 | n5 |
--  +----+----+----+          +----+----+
--```
--
-- Once the system is running, the control node spins up a set of logically
-- single-threaded processes (see `molly.thread`), each with its own client for
-- the distributed system.
--
-- A generator (see `molly.gen`) generates new operations (see `molly.op`)
-- for each process to perform. Processes then apply those operations to the
-- system using their clients, see `molly.client`. The start and end of each
-- operation is recorded in a history, see `molly.history`. While performing
-- operations, a special nemesis process (see `molly.nemesis`) introduces
-- faults into the system - also scheduled by the generator.
--
-- Finally, the DB is turn down. Molly uses a checker (see `molly.checker`)
-- to analyze the test's history for correctness, and to generate reports,
-- graphs, etc. The test, history, analysis, and any supplementary results are
-- written to the filesystem for later review.
--
-- <!-- TODO: https://jepsen.io/consistency -->
--
--### Performance Tips
--
-- **Disable debug mode**: by default tests enables type checking, see
-- statements with `dev_checks()` in source code, and code coverage gathering.
-- This requires using Lua `debug` module, that can significantly slowdown of
-- execution (about 1.6 times). You can control it with environment variable
-- `DEV`, to run tests with disabled type checking and code coverage: `DEV=OFF
-- make test`.
--
-- **Disable verbose mode**: see description of `verbose` mode.
--
-- **Use fibers**: TODO: performance of fibers vs coroutines.

local checks = require('molly.dev_checks')
local math = require('math')

local clock = require('molly.clock')
local history_lib = require('molly.history')
local log = require('molly.log')
local threadpool = require('molly.threadpool')
local client = require('molly.client')
local is_tarantool = require('molly.utils').is_tarantool

local has_fun, _ = pcall(require, 'fun')
local has_json, _ = pcall(require, 'molly.json')

local function print_summary(total_time, history, opts)
    checks('number', 'table', 'table')

    log.debug('Running test %.3fs with %d thread(s)', total_time, opts.threads)
    if opts.nodes ~= nil then
        for _, addr in pairs(opts.nodes) do
            log.debug('- %s', addr)
        end
        log.debug('')
    end

    local ops_completed = history:ops_completed()
    local ops_planned = history:ops_planned()
    log.debug('Total planned requests: %-35s', tostring(ops_planned))
    if ops_completed ~= 0 then
        log.debug('Total completed requests: %-35s', tostring(ops_completed))
        local rps = math.floor(ops_completed / total_time)
        log.debug('Requests per sec: %-35s', tostring(rps))
    end
end

function checkers.workload_opts(opts)
    return opts.client ~= nil and type(opts.client) == 'table' and
           opts.generator ~= nil and type(opts.generator) == 'table' and
           (opts.checker == nil or type(opts.generator) == 'table')
end

function checkers.test_opts(opts)
    return (opts.create_reports == nil or type(opts.create_reports) == 'boolean') and
           (opts.threads == nil or type(opts.threads) == 'number') and
           (opts.thread_type == nil or
            opts.thread_type == 'fiber' or
            opts.thread_type == 'coroutine') and
           (opts.time_limit == nil or type(opts.time_limit) == 'number') and
           (opts.nodes == nil or type(opts.nodes) == 'table')
end

--- Create test and run.
--
-- @table workload Table with workload options.
-- @param workload.client Workload client. Learn more about creating clients in
-- `molly.client`.
-- @table workload.generator Generator of operations used in test workload.
-- Generator must be a table with `unwrap()` method that returns an iterator
-- triplet. You can make generator youself or use `molly.gen` module.
-- @param[opt] workload.checker Function for checking history in workload.
-- @table[opt] opts Table with test options.
-- @boolean[opt] opts.create_reports Option to control creating reports,
-- disabled by default. When enabled a number of files created:
--
--  - history.txt with plain history;
--  - history.json with history encoded to JSON;
--
-- @number[opt] opts.threads Number of threads in a test workload, default
-- value is 1.
-- @boolean[opt] opts.verbose shows details about the results and progress of
-- running test. This can be especially useful when the results might not be
-- obvious. For example, if you want to see the progress of testing as it
-- setup, teardown or invokes operations, you can use the 'verbose' option. In
-- the beginning, you may find it useful to use 'verbose' at all times; when
-- you are more accustomed to `molly`, you will likely want to use it at
-- certain times but not at others. Disabled by default.
-- Take into account that logging to standart output is a slow operation and
-- with enabled verbose mode `molly` logs status of every operation before
-- and after it's invocation and this may slowdown overall testing performance
-- significantly. It is recommended to disable verbose mode in a final testing
-- and use it only for debugging.
-- @string[opt] opts.thread_type Type of threads used in a test workload.
-- Possible values are 'fiber' (see `molly.thread_fiber`) and 'coroutine' (see
-- `molly.thread_coroutine`), default value is 'fiber' on Tarantool and
-- 'coroutine' on LuaJIT. Learn more about possible thread types in
-- `molly.thread`.
-- @number[opt] opts.time_limit Number of seconds to limit time of testing. By
-- default testing time is endless and limited by a number of operations
-- produced by generator.
-- @table[opt] opts.nodes A table that contains IP addresses of nodes
-- participated in testing.
--
-- @see molly.gen
-- @see molly.client
--
-- @return true on success or nil with error
--
-- @usage
--
-- local test_options = {
--     create_reports = true,
--     thread_type = 'fiber',
--     threads = 5,
--     nodes = {
--         '127.0.0.1'
--     }
-- }
-- local ok, err = runner.run_test({
--     client = client.new(),
--     generator = gen_lib.cycle(gen_lib.iter({ r, w })):take(1000)
-- }, test_options)
--
-- @function run_test
local function run_test(workload, opts)
    checks('workload_opts', 'test_opts')

    if not has_json then
        error('JSON module is not available')
    end
    if not has_fun then
        error('Lua functional module is not available')
    end

    opts = opts or {}
    opts.logging = opts.create_reports or false
    opts.nodes = opts.nodes or {}
    opts.threads = opts.threads or 1
    opts.thread_type = opts.thread_type or
                       (is_tarantool() and 'fiber') or 'coroutine'

    if opts.verbose or os.getenv('DEV') == 'ON' then
        log.level = 'debug'
    end

    local unwrap = workload.generator.unwrap
    if unwrap == nil or type(workload.generator.unwrap) ~= 'function' then
        error('Generator must have an unwrap method')
    end

    -- Start workload.
    local history = history_lib.new()
    local total_time_begin = clock.proc()
    local pool = threadpool.new(opts.thread_type, opts.threads)
    local ok, err = pool:start(client.run, {
        client = workload.client,
        gen = workload.generator,
        history = history,
        nodes = opts.nodes,
    })
    if not ok then
        return nil, err
    end
    local total_passed_sec = clock.proc() - total_time_begin

    -- Summary.
    print_summary(total_passed_sec, history, opts)

    if opts.create_reports == true then
        local log_txt = 'history.txt'
        local log_json = 'history.json'

        local fp = io.open(log_txt, 'w')
        fp:write(history:to_txt())
        fp:close()

        fp = io.open(log_json, 'w')
        fp:write(history:to_json())
        fp:close()

        log.debug('File with operations history (plain text):    %s', log_txt)
        log.debug('File with operations history (JSON):          %s', log_json)
    end

    return true
end

return {
    run_test = run_test,
}
