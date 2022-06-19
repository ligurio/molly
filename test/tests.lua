--
-- Unit and integrations tests for Molly.
--

require('test.coverage').enable()

local lunit = require('lunitx')
local math = require('math')
local os = require('os')

local helpers = require('test.helpers')

local molly = require('molly')

local client = require('molly.client')
local clock = require('molly.clock')
local gen_lib = molly.gen
local history = require('molly.history')
local json = require('molly.json')
local log = molly.log
local op_lib = require('molly.op')
local runner = molly.runner
local tests = molly.tests
local threadpool = require('molly.threadpool')
local utils = molly.utils

local seed = os.time()
math.randomseed(seed)

local function lunit_TestCase(name)
   return lunit.module(name, 'seeall')
end

local clock_suite = lunit_TestCase('clock')

function clock_suite.test_monotonic64()
    clock.monotonic64()
end

function clock_suite.test_monotonic()
    local time = clock.monotonic()
    lunit.assert_equal(type(time), 'number')
end

function clock_suite.test_proc()
    local time = clock.proc()
    lunit.assert_equal(type(time), 'number')
end

function clock_suite.test_sleep()
    clock.sleep(0.1)
end

function clock_suite.test_dt()
    local dt = clock.dt()
    lunit.assert_string(dt)
end

local history_suite = lunit_TestCase('history')

function history_suite.test_new()
    local h = history.new()
    lunit.assert_not_equal(h, nil)
end

function history_suite.test_add()
    local h = history.new()
    local ok = h:add({
        type = 'invoke',
        f = 'ok',
        value = 10
    })
    lunit.assert_true(ok)
end

function history_suite.test_to_txt()
    -- Skip test due to a problem with SIGSEGV on running regression tests with
    -- LuaJIT, see #1.
    if utils.is_tarantool() == false then
        return
    end

    local h = history.new()
    local ok = h:add({
        f = 'read',
        type = 'invoke',
        process = 1,
    })
    lunit.assert_true(ok)
    lunit.assert_equal(h:to_txt(), "\n  1    invoke     read       null      ")
end

function history_suite.test_ops_completed()
    local h = history.new()
    h:add({ type = 'ok', value = 2 })
    h:add({ type = 'fail', value = 5 })
    h:add({ type = 'fail', value = 3 })
    h:add({ type = 'invoke', value = 6 })

    local n = h:ops_completed()
    lunit.assert_equal(n, 3)
end

function history_suite.test_ops_planned()
    local h = history.new()
    h:add({ type = 'invoke', value = 2 })
    h:add({ type = 'fail', value = 5 })
    h:add({ type = 'fail', value = 3 })
    h:add({ type = 'ok', value = 6 })
    local n = h:ops_planned()
    lunit.assert_equal(n, 1)
end

function history_suite.test_to_json()
    -- Skip test due to a problem with SIGSEGV on running regression tests with
    -- LuaJIT, see #1.
    if utils.is_tarantool() == false then
        return
    end

    local h = history.new()
    h:add({ type = 'ok', value = 2 })
    h:add({ type = 'fail', value = 5 })
    h:add({ type = 'fail', value = 3 })
    h:add({ type = 'invoke', value = 6 })
    local str = h:to_json()
    lunit.assert_equal(str,
        '[{"type":"ok","value":2},{"type":"fail","value":5},{"type":"fail","value":3},{"type":"invoke","value":6}]')
end

local log_suite = lunit_TestCase('log')

function log_suite.test_outfile()
    local log_name = os.tmpname()
    log.outfile = log_name
    log.debug('Hello, Molly!')
    os.remove(log_name)
end

function log_suite.test_debug()
    -- Setup
    local log_level = log.level
    log.outfile = os.tmpname()

    log.debug('Hello, Molly!')

    -- Teardown
    log.level = log_level
    os.remove(log.outfile)
    log.outfile = nil
end

local op_suite = lunit_TestCase('op')

function op_suite.test_to_string_type_invoke()
    -- Skip test due to a problem with SIGSEGV on running regression tests with
    -- LuaJIT, see #1.
    if utils.is_tarantool() == false then
        return
    end

    local op = {
        f = 'read',
        value = 10,
        type = 'invoke',
    }

    local str = op_lib.to_string(op)
    lunit.assert_equal(str, 'invoke     read       10        ')
end

function op_suite.test_to_string_type_ok()
    -- Skip test due to a problem with SIGSEGV on running regression tests with
    -- LuaJIT, see #1.
    if utils.is_tarantool() == false then
        return
    end

    local op = {
        f = 'read',
        value = 10,
        type = 'ok',
    }

    local str = op_lib.to_string(op)
    lunit.assert_equal(str, 'ok         read       10        ')
end

function op_suite.test_to_string_type_fail()
    -- Skip test due to a problem with SIGSEGV on running regression tests with
    -- LuaJIT, see #1.
    if utils.is_tarantool() == false then
        return
    end

    local op = {
        f = 'read',
        value = 10,
        type = 'fail',
    }

    local str = op_lib.to_string(op)
    lunit.assert_equal(str, 'fail       read       10        ')
end

function op_suite.test_is_completed_type_ok()
    local op = {
        type = 'ok',
    }
    lunit.assert_true(op_lib.is_completed(op))
end

function op_suite.test_is_completed_type_fail()
    local op = {
        type = 'fail',
    }
    lunit.assert_true(op_lib.is_completed(op))
end

function op_suite.test_is_completed_type_invoke()
    local op = {
        type = 'invoke',
    }
    lunit.assert_false(op_lib.is_completed(op))
end

function op_suite.test_is_planned_type_invoke()
    local op = {
        type = 'invoke',
    }
    lunit.assert_true(op_lib.is_planned(op))
end

function op_suite.test_is_planned_type_ok()
    local op = {
        type = 'ok',
    }
    lunit.assert_false(op_lib.is_planned(op))
end

function op_suite.test_is_planned_type_fail()
    local op = {
        type = 'fail',
    }
    lunit.assert_false(op_lib.is_planned(op))
end

local utils_suite = lunit_TestCase('utils')

function utils_suite.test_cwd()
    lunit.assert_not_equal(utils.cwd(), '')
end

function utils_suite.test_chdir()
    local cwd = utils.cwd()
    lunit.assert_true(utils.chdir('/tmp'))
    lunit.assert_equal(utils.cwd(), '/tmp')
    lunit.assert_true(utils.chdir(cwd))

    lunit.assert_false(utils.chdir('xxx'))
end

function utils_suite.test_setenv()
    lunit.assert_true(utils.setenv('MOLLY', 1))
    lunit.assert_equal(os.getenv('MOLLY'), '1')
    lunit.assert_true(utils.setenv('MOLLY'))
    lunit.assert_equal(os.getenv('MOLLY'), nil)
end

function utils_suite.test_basename()
    lunit.assert_equal(utils.basename('/home/sergeyb/sources/molly/README.md'), 'README.md')
end

local gen_suite = lunit_TestCase('gen')

local OP_TYPE = 1
local OP_VAL = 3

function gen_suite.test_range()
    local gen, param, state = gen_lib.range(1, 2)
    local item = gen(param, state)
    lunit.assert_equal(item, 1)
end

function gen_suite.test_time_limit()
    local timeout = 0.01
    local start_time = clock.proc()
    for _ in gen_lib.time_limit(gen_lib.range(1, 1000), timeout) do
        -- Nothing.
    end
    local passed_time = clock.proc() - start_time
    local eps = 1
    lunit.assert_true(passed_time - timeout < eps,
        ('Passed time %f, timeout %f'):format(passed_time, timeout))
end

local tests_suite = lunit_TestCase('tests')

function tests_suite.test_rw_register_gen_take()
    local num = 5
    local n = tests.rw_register_gen():take(5):length()
    lunit.assert_equal(n, num)
end

function tests_suite.test_rw_register_gen_op()
    local gen, param, state = tests.rw_register_gen()
    local _, op_func, _ = gen(param, state)
    local op = op_func()

    local IDX_MOP_TYPE = 1
    local IDX_MOP_KEY = 2
    local IDX_MOP_VAL = 3

    local mop = op.value[1]
    lunit.assert_equal(type(mop), 'table')
    local mop_key = mop[IDX_MOP_KEY]
    lunit.assert_equal(type(mop_key) == 'string', true)
    local mop_type = mop[IDX_MOP_TYPE]
    lunit.assert_equal(mop_type == 'r' or mop_type == 'append', true)
    local mop_val = mop[IDX_MOP_VAL]
    lunit.assert_equal(type(mop_val) == 'number' or  mop_val == json.NULL, true)
end

function tests_suite.test_list_append_gen_take()
    -- FIXME: Broken.
    if true then
        return
    end

    local num = 5
    local n = gen_lib.take(num, tests.list_append_gen()):length()
    lunit.assert_equal(n, num)
end

function tests_suite.test_list_append_gen_op()
    -- FIXME: Broken.
    if true then
        return
    end

    local gen, param, state = tests.list_append_gen()
    local val = gen(param, state)
    local mop = val.value[1]
    local op_type = mop[OP_TYPE]
    local op_val = mop[OP_VAL]
    lunit.assert_equal(op_type == 'r' or op_type == 'w', true)
    lunit.assert_equal(type(op_val) == 'number' or op_val == json.NULL, true)
end

local runner_suite = lunit_TestCase('runner')

function runner_suite.test_run_test_generator_wo_unwrap()
    local workload_opts = {
        client = {},
        generator = {},
    }
    local test_opts = {}
    local ok, err = pcall(runner.run_test, workload_opts, test_opts)
    lunit.assert_false(ok)
    local res = string.find(err, 'Generator must have an unwrap method')
    lunit.assert_not_equal(res, nil)
end

function runner_suite.test_run_test_broken_setup()
    local cl = client.new()
    cl.setup = function() assert(nil, 'broken setup') end

    local workload_opts = {
        client = cl,
        generator = {
            unwrap = function() return end
        },
    }
    local test_opts = {
        nodes = {
            'a',
        }
    }
    local ok = runner.run_test(workload_opts, test_opts)
    lunit.assert_equal(ok, true)
end

function runner_suite.test_run_test_broken_teardown()
    local cl = client.new()
    cl.teardown = function()
        assert(nil, 'broken teardown')
    end

    local workload_opts = {
        client = cl,
        generator = {
            unwrap = function() return end
        },
    }
    local test_opts = {
        nodes = {
            'a',
        }
    }
    local ok = runner.run_test(workload_opts, test_opts)
    lunit.assert_equal(ok, true)
end

------------------------
-- Integration tests  --
------------------------

local test_dict = {}

local client_dict = client.new()

client_dict.invoke = function(self, op)
    local k = 42
    local val = op.value[1]
    if val[OP_TYPE] == 'r' then
        val[OP_VAL] = test_dict[k]
    elseif val[OP_TYPE] == 'w' then
        test_dict.k = op.v
    else
        error('Unknown operation')
    end

    return {
        value = { val },
        f = op.f,
        type = 'ok',
        process = op.process,
    }
end

-- Run a test that generates random read and write operations for Lua
-- dictionary.
local function run_test_dict(thread_type)
    local test_options = {
        create_reports = true,
        thread_type = thread_type,
        threads = 5,
        nodes = { 'a', 'b', 'c' }, -- Required for better code coverage.
    }
    local ok, err = runner.run_test({
        client = client_dict,
        generator = tests.rw_register_gen():take(100)
    }, test_options)

    lunit.assert_equal(err, nil)
    lunit.assert_true(ok)

    if ok == true and test_options.create_reports == true then
        lunit.assert_true(helpers.file_exists('history.txt'))
        lunit.assert_true(helpers.file_exists('history.json'))

        -- Cleanup.
        if os.getenv('DEV') ~= 'ON' then
            os.remove('history.json')
            os.remove('history.txt')
        end
    end
    log.debug('Random seed: %s', seed)

    return true
end

local threadpool_suite = lunit_TestCase('threadpool')

function threadpool_suite.test_cancel()
    -- TODO: Failed with LuaJIT.
    if utils.is_tarantool() == false then
        return
    end

    local pool = threadpool.new('coroutine', 1)
    local res = pool:cancel()
    lunit.assert_true(res)
end

function threadpool_suite.test_new_thread_fiber()
    if utils.is_tarantool() then
        local pool = threadpool.new('fiber', 1)
        lunit.is_table(pool)
    end
end

function threadpool_suite.test_new_thread_coroutine()
    local pool = threadpool.new('coroutine', 1)
    lunit.is_table(pool)
end

function threadpool_suite.test_new_thread_unknown()
    local ok, err = pcall(threadpool.new, 'xxx', 1)
    lunit.assert_false(ok)
    local res = string.find(err, 'No thread library with type "xxx"')
    lunit.assert_not_equal(res, nil)
end

local integration_suite = lunit_TestCase('integration')

function integration_suite.test_fiber()
    if utils.is_tarantool() then
        lunit.assert_true(run_test_dict('fiber'))
    end
end

function integration_suite.test_coroutine()
    lunit.assert_true(run_test_dict('coroutine'))
end

------------------------
---- Run the tests  ----
------------------------

require('test.coverage').shutdown()

local stats = lunit.main()
if stats.errors > 0 or stats.failed > 0 then
    os.exit(1)
end
