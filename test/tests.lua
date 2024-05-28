--
-- Unit and integration tests for Molly.
--

require('test.coverage').enable()

local math = require('math')
local os = require('os')

local helpers = require('test.helpers')
local test = require('test.tap').test('molly')

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

test:plan(11)

test:test('clock', function(test)
    test:plan(5)

    local res = clock.monotonic64()
    local res_tarantool = type(res) == 'cdata' and utils.is_tarantool()
    local res_luajit = type(res) == 'number' and not utils.is_tarantool()
    test:is(res_tarantool or res_luajit, true, "clock.monotonic64()")
    test:isnumber(clock.monotonic(), "clock.monotonic()")
    test:isnumber(clock.proc(), "clock.proc()")
    test:isnil(clock.sleep(0.1), "clock.sleep()")
    test:isstring(clock.dt(), "clock.dt()")
end)

test:test('history', function(test)
    test:plan(9)
    test:isnt(history.new(), nil, "history.new()")

    local h = history.new()
    local ok = h:add({ type = 'invoke', f = 'ok', value = 10 })
    test:is(ok, true, "history_obj:add()")

    h = history.new()
    ok = h:add({ f = 'read', type = 'invoke', process = 1, })
    test:is(ok, true, "history_obj:add()")
    test:is(h:to_txt(), "\n  1    invoke     read       null      ", "history_obj:to_txt()")

    h = history.new()
    h:add({ type = 'ok', value = 2 })
    h:add({ type = 'fail', value = 5 })
    h:add({ type = 'fail', value = 3 })
    h:add({ type = 'invoke', value = 6 })
    test:is(h:ops_completed(), 3, "history_obj:ops_completed()")

    h = history.new()
    h:add({ type = 'invoke', value = 2 })
    h:add({ type = 'fail', value = 5 })
    h:add({ type = 'fail', value = 3 })
    h:add({ type = 'ok', value = 6 })
    test:is(h:ops_planned(), 1, "history_obj:ops_planned()")

    h = history.new()
    h:add({ type = 'ok', value = 2 })
    local ref_str = '[{"type":"ok","value":2}]'
    test:is(h:to_json(), ref_str, "history_obj:to_json(): { type = 'ok' }")

    h = history.new()
    h:add({ type = 'fail', value = 3 })
    ref_str = '[{"type":"fail","value":3}]'
    test:is(h:to_json(), ref_str, "history_obj:to_json(): { type = 'fail' }")

    h = history.new()
    h:add({ type = 'invoke', value = 6 })
    ref_str = '[{"type":"invoke","value":6}]'
    test:is(h:to_json(), ref_str, "history_obj:to_json(): { type = 'invoke' }")
end)

test:test('op', function(test)
    test:plan(9)
    local op = { f = 'read', value = 10, type = 'invoke' }
    local str = op_lib.to_string(op)
    test:is(str, 'invoke     read       10        ', "op.to_string() { type = 'invoke'}")

    op = { f = 'read', value = 10, type = 'ok' }
    str = op_lib.to_string(op)
    test:is(str, 'ok         read       10        ', "op.to_string() { type = 'ok' }")

    op = { f = 'read', value = 10, type = 'fail' }
    str = op_lib.to_string(op)
    test:is(str, 'fail       read       10        ', "op.to_string() { type = 'fail' }")

    op = { type = 'ok' }
    test:is(op_lib.is_completed(op), true, "op.is_completed() { type = 'ok' }")

    op = { type = 'fail' }
    test:is(op_lib.is_completed(op), true, "op.is_completed() { type = 'fail' }")

    op = { type = 'invoke' }
    test:is(op_lib.is_completed(op), false, "op.is_completed() { type = 'invoke' }")

    op = { type = 'ok' }
    test:is(op_lib.is_planned(op), false, "op.is_planned() { type = 'ok' }")

    op = { type = 'fail' }
    test:is(op_lib.is_planned(op), false, "op.is_planned() { type = 'fail' }")

    op = { type = 'invoke' }
    test:is(op_lib.is_completed(op), false, "op.is_planned() { type = 'invoke' }")
end)

test:test('utils', function(test)
    test:plan(10)

    test:isnt(utils.cwd(), '', "utils.cwd()")
    local cwd = utils.cwd()
    test:is(utils.chdir('/tmp'), true, "utils.chdir()")
    test:is(utils.cwd(), '/tmp', "utils.cwd()")
    test:is(utils.chdir(cwd), true, "utils.chdir()")
    test:is(utils.chdir('xxx'), false, "utils.chdir()")

    test:is(utils.setenv('MOLLY', 1), true, "utils.setenv()")
    test:is(os.getenv('MOLLY'), '1', "os.getenv()")
    test:is(utils.setenv('MOLLY'), true, "utils.setenv()")
    test:isnil(os.getenv('MOLLY'), "os.getenv()")

    test:is(utils.basename('/home/sergeyb/sources/molly/README.md'), 'README.md', "utils.basename()")
end)

local OP_TYPE = 1
local OP_VAL = 3

test:test('gen', function(test)
    test:plan(2)

    local gen, param, state = gen_lib.range(1, 2)
    local item = gen(param, state)
    test:is(item, 1, "gen.range()")

    local timeout = 0.01
    local start_time = clock.proc()
    for _ in gen_lib.time_limit(gen_lib.range(1, 1000), timeout) do
        -- Nothing.
    end
    local passed_time = clock.proc() - start_time
    local eps = 1
    test:ok(passed_time - timeout < eps, "gen.time_limit()")
end)

test:test('tests.cas_register_gen', function(test)
    test:plan(4)

    local num = 5
    local n = tests.cas_register_gen():take(5):length()
    test:is(n, num, 'tests.cas_register_gen(): length')

    local gen, param, state = tests.cas_register_gen()
    local _, res = gen(param, state)
    res = res()
    local f = res.f
    local value = res.value
    test:ok(f == 'cas' or
	        f == 'write' or
			f == 'read', 'tests.cas_register_gen(): function')
    test:is(type(value), 'table', 'tests.cas_register_gen(): value type')
    if f == 'cas' then
        test:ok(#value, 2, 'tests.cas_register_gen(): cas value')
    end
    if f == 'read' then
        test:ok(#value, 0, 'tests.cas_register_gen(): read value')
    end
    if f == 'write' then
        test:ok(#value, 1, 'tests.cas_register_gen(): write value')
    end
end)

local IDX_MOP_TYPE = 1
local IDX_MOP_KEY = 2
local IDX_MOP_VAL = 3

test:test('tests.rw_register_gen', function(test)
    test:plan(5)

    local num = 5
    local n = tests.rw_register_gen():take(5):length()
    test:is(n, num, "tests.rw_register_gen(): length")

    local gen, param, state = tests.rw_register_gen()
    local _, op_func, _ = gen(param, state)
    local op = op_func()
    local mop = op.value[1]
    test:is(type(mop), 'table', "tests.rw_register_gen(): mop")
    local mop_key = mop[IDX_MOP_KEY]
    test:is(type(mop_key), 'string', "tests.rw_register_gen(): mop key")
    local mop_type = mop[IDX_MOP_TYPE]
    test:is(mop_type == 'r' or mop_type == 'append', true, "tests.rw_register_gen(): mop type")
    local mop_val = mop[IDX_MOP_VAL]
    test:is(mop_val == 'number' or mop_val == json.NULL, true, "tests.rw_register_gen(): mop value")
end)

test:test('tests.list_append_gen', function(test)
    test:plan(2)

    local gen, param, state = tests.list_append_gen()
    local _, val = gen(param, state)
    local mop = val.value[1]
    local op_type = mop[OP_TYPE]
    local op_val = mop[OP_VAL]
    test:is(op_type == 'r' or op_type == 'append', true, "tests.list_append_gen(): op type")
    test:is(type(op_val) == 'number' or op_val == json.NULL, true, "tests.list_append_gen(): op value")
end)

test:test('runner', function(test)
    test:plan(4)

    local workload_opts = {
        client = {},
        generator = {},
    }
    local test_opts = {}
    local ok, err = pcall(runner.run_test, workload_opts, test_opts)
    test:is(ok, false, "runner.run_test(): invalid generator")
    local res = string.find(err, 'Generator must have an unwrap method')
    test:isnt(res, nil, "runner.run_test(): err is not nil")

    local cl = client.new()
    cl.setup = function() assert(nil, 'broken setup') end
    workload_opts = {
        client = cl,
        generator = {
            unwrap = function() return end
        },
    }
    test_opts = {
        nodes = {
            'a',
        }
    }
    ok = runner.run_test(workload_opts, test_opts)
    test:is(ok, true, "runner.run_test(): broken setup")

    cl = client.new()
    cl.teardown = function()
        assert(nil, 'broken teardown')
    end
    workload_opts = {
        client = cl,
        generator = {
            unwrap = function() return end
        },
    }
    test_opts = {
        nodes = {
            'a',
        }
    }
    ok = runner.run_test(workload_opts, test_opts)
    test:is(ok, true, "runner.run_test(): broken teardown")
end)

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
local run_test_dict = function(thread_type)
    if utils.is_tarantool() == false and thread_type == 'fiber' then
        return false
    end

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

    assert(err == nil, "run_test_dict: err is not nil")
    assert(ok, "run_test_dict: ok is not true")

    if ok == true and test_options.create_reports == true then
        assert(helpers.file_exists('history.txt'), "history.txt does not exist")
        assert(helpers.file_exists('history.json'), "history.json does not exist")

        -- Cleanup.
        if os.getenv('DEV') ~= 'ON' then
            os.remove('history.json')
            os.remove('history.txt')
        end
    end
    log.debug('Random seed: %s', seed)

    return true
end

test:test("threadpool", function(test)
    test:plan(5)

    local pool = threadpool.new('coroutine', 1)
    local res = pool:cancel()
    test:is(res, true, "threadpool.new('coroutine'): cancel")

    pool = threadpool.new('coroutine', 1)
    test:is(type(pool), 'table', "threadpool.new('coroutine'): type")

    local ok
    ok, pool = pcall(threadpool.new, 'fiber', 1)
    local res_tarantool = ok == true and
                          type(pool) == 'table' and
                          utils.is_tarantool() == true
    local res_luajit = ok == false and
                       string.find(pool, 'No thread library with type "fiber"') ~= nil and
                       utils.is_tarantool() == false
    test:is(res_luajit or res_tarantool, true, "threadpool.new('fiber'): type")

    local err
    ok, err = pcall(threadpool.new, 'xxx', 1)
    test:is(ok, false, "threadpool.new('xxx'): ok is true")
    res = string.find(err, 'No thread library with type "xxx"')
    test:isnt(res, nil, "threadpool.new('xxx'): error is correct")
end)

test:test("threads", function(test)
    test:plan(2)
    test:is(run_test_dict('coroutine'), true, "run_test_dict: coroutine")

    local res = false
    if utils.is_tarantool() then
        res = true
    end
    test:is(run_test_dict('fiber'), res, "run_test_dict: fiber")
end)

------------------------
---- Run the tests  ----
------------------------

require('test.coverage').shutdown()

os.exit(test:check() == true and 0 or 1)
