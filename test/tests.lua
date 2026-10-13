--
-- Unit and integration tests for Molly.
--

require('test.coverage').enable()

local math = require('math')
local os = require('os')
local ffi = require('ffi')

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
local thread = require('molly.thread')
local utils = molly.utils

-- A thread backend is available when its implementation is
-- loaded by the runtime: 'fiber' only under Tarantool,
-- 'coroutine' always.
local function thread_backend_available(backend)
    if backend == 'fiber' then
        return utils.is_tarantool()
    end
    return true
end

local seed = os.time()
math.randomseed(seed)

test:plan(43)

test:test('clock', function(test)
    test:plan(7)

    local res = clock.monotonic64()
    local res_tarantool = type(res) == 'cdata' and utils.is_tarantool()
    local res_luajit = type(res) == 'number' and not utils.is_tarantool()
    test:is(res_tarantool or res_luajit, true, "clock.monotonic64()")
    test:isnumber(clock.monotonic(), "clock.monotonic()")
    -- The clocks are sampled in separate calls, so the difference
    -- includes scheduling jitter. The tolerance is wide enough to
    -- tolerate a delay between the calls while still catching a
    -- unit mismatch (seconds vs nanoseconds).
    local diff = math.abs(clock.monotonic() -
        assert(tonumber(clock.monotonic64())) / 10^9)
    test:ok(diff < 1, "clock.monotonic() in seconds")
    test:isnumber(clock.proc(), "clock.proc()")
    test:isnil(clock.sleep(0.1), "clock.sleep()")
    local before = clock.monotonic()
    clock.sleep(0.05)
    test:ok(clock.monotonic() - before >= 0.04, "clock.sleep() in seconds")
    test:isstring(clock.dt(), "clock.dt()")
end)

test:test('json.NULL', function(test)
    test:plan(2)

    test:is(json.encode({ json.NULL, 5 }), '[null,5]',
            'json.NULL encodes to null')
    test:is(json.encode({ 'r', 1, json.NULL }), '["r",1,null]',
            'json.NULL is preserved in arrays')
end)

test:test('history', function(test)
    test:plan(12)
    test:isnt(history.new(), nil, "history.new()")

    local h = history.new()
    local ok = h:add({ type = 'invoke', f = 'ok', value = 10 })
    test:is(ok, true, "history_obj:add()")

    h = history.new()
    ok = h:add({ f = 'read', type = 'invoke', process = 1, })
    test:is(ok, true, "history_obj:add()")
    test:is(h:to_txt(),
        "\n  1    invoke     read       null      ", "history_obj:to_txt()")

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
    local history_json = h:to_json()
    test:like(history_json, '"type":"ok"', ":to_json() type is ok")
    test:like(history_json, '"value":2', ":to_json() value is 2")

    h = history.new()
    h:add({ type = 'fail', value = 3 })
    history_json = h:to_json()
    test:like(history_json, '"type":"fail"', ":to_json() type is fail")
    test:like(history_json, '"value":3', ":to_json() value is 3")

    h = history.new()
    h:add({ type = 'invoke', value = 6 })
    history_json = h:to_json()
    test:like(history_json, '"type":"invoke"', ":to_json() type is invoke")
    test:like(history_json, '"value":6', ":to_json() value is 6")
end)

test:test('history.is_well_formed', function(test)
    test:plan(30)

    -- Collect messages of all findings for assertions.
    local function messages(findings)
        local res = {}
        for _, item in ipairs(findings or {}) do
            table.insert(res, item.message)
        end
        return table.concat(res, '\n')
    end

    -- Build a history object from an array of operations.
    local function hist(ops)
        local h = history.new()
        for _, o in ipairs(ops) do
            h:add(o)
        end
        return h
    end

    -- A well-formed history: invoke/ok, invoke/fail and
    -- invoke/info pairs plus a nemesis operation.
    local valid = {
        { type = 'invoke', f = 'read', process = 1, index = 1, time = 1,
          debug = true },
        { type = 'ok', f = 'read', process = 1, index = 2, time = 2 },
        { type = 'invoke', f = 'write', process = 2, index = 3, time = 3 },
        { type = 'fail', f = 'write', process = 2, index = 4, time = 4 },
        { type = 'invoke', f = 'read', process = 3, index = 5, time = 5 },
        { type = 'info', f = 'read', process = 3, index = 6, time = 6 },
        { type = 'info', f = 'start', process = 'nemesis', index = 7,
          time = 7 },
    }
    test:is(hist(valid):is_well_formed(), true,
        'history.is_well_formed(): a well-formed history is valid')
    test:is(history.is_well_formed(valid), true,
        'history.is_well_formed(): a plain array is valid')

    -- A completion without an invocation.
    local ok, findings = hist({
        { type = 'ok', f = 'read', process = 1, index = 1 },
    }):is_well_formed()
    test:is(ok, false, 'history.is_well_formed(): completion without invoke')
    test:like(messages(findings), 'completed without invoke',
        'history.is_well_formed(): completion without invoke message')

    -- Two invocations in a row on one process.
    ok = hist({
        { type = 'invoke', process = 1, index = 1 },
        { type = 'invoke', process = 1, index = 2 },
    }):is_well_formed()
    test:is(ok, false, 'history.is_well_formed(): process invoked twice')

    -- An invocation after a crash (an info completion).
    ok = hist({
        { type = 'invoke', process = 1, index = 1 },
        { type = 'info', process = 1, index = 2 },
        { type = 'invoke', process = 1, index = 3 },
    }):is_well_formed()
    test:is(ok, false, 'history.is_well_formed(): invocation after info')

    -- A dangling invocation.
    ok, findings = hist({
        { type = 'invoke', process = 1, index = 1, time = 1 },
    }):is_well_formed()
    test:is(ok, false, 'history.is_well_formed(): dangling invocation')
    test:is(findings and findings[1] and findings[1]['index'], 1,
        'history.is_well_formed(): dangling invoke has an index')

    -- An invalid operation type.
    ok = hist({
        { type = 'unknown', process = 1, index = 1 },
    }):is_well_formed()
    test:is(ok, false, 'history.is_well_formed(): an invalid type')

    -- A nemesis with a type other than info.
    ok = hist({
        { type = 'ok', process = 'nemesis', index = 1 },
    }):is_well_formed()
    test:is(ok, false, 'history.is_well_formed(): a bad nemesis operation')

    -- A duplicate index.
    ok = hist({
        { type = 'invoke', process = 1, index = 1 },
        { type = 'ok', process = 1, index = 1 },
    }):is_well_formed()
    test:is(ok, false, 'history.is_well_formed(): a duplicate index')

    -- A non-ascending index.
    ok = hist({
        { type = 'invoke', process = 1, index = 2 },
        { type = 'ok', process = 1, index = 1 },
    }):is_well_formed()
    test:is(ok, false, 'history.is_well_formed(): a non-ascending index')

    -- A non-monotonic time is a warning, not an error.
    ok, findings = hist({
        { type = 'invoke', process = 1, index = 1, time = 2 },
        { type = 'ok', process = 1, index = 2, time = 1 },
    }):is_well_formed()
    test:is(ok, true, 'history.is_well_formed(): non-monotonic time is valid')
    local has_warning = false
    for _, item in ipairs(findings or {}) do
        if item.severity == 'warning' then
            has_warning = true
        end
    end
    test:is(has_warning, true,
        'history.is_well_formed(): non-monotonic time is a warning')

    -- An operation without a process.
    ok, findings = hist({
        { type = 'invoke', index = 1 },
    }):is_well_formed()
    test:is(ok, false, 'history.is_well_formed(): an operation without process')
    test:like(messages(findings), 'has no process',
        'history.is_well_formed(): a missing process message')

    -- A non-numeric index does not crash the checker.
    ok = hist({
        { type = 'invoke', process = 1, index = '1' },
    }):is_well_formed()
    test:is(ok, false, 'history.is_well_formed(): a non-numeric index')

    -- A fractional index is not a valid index.
    ok = hist({
        { type = 'invoke', process = 1, index = 1.5 },
    }):is_well_formed()
    test:is(ok, false, 'history.is_well_formed(): a fractional index')

    -- A process must be a number or a string.
    ok = hist({
        { type = 'info', process = {} },
    }):is_well_formed()
    test:is(ok, false,
        'history.is_well_formed(): a non-numeric process')

    -- A non-numeric time.
    ok = hist({
        { type = 'invoke', process = 1, index = 1, time = 'now' },
    }):is_well_formed()
    test:is(ok, false, 'history.is_well_formed(): a non-numeric time')

    -- A missing time.
    ok = hist({
        { type = 'invoke', process = 1, index = 1 },
        { type = 'ok', process = 1, index = 2 },
    }):is_well_formed()
    test:is(ok, false, 'history.is_well_formed(): a missing time')

    -- A fractional time is not a valid time.
    ok = hist({
        { type = 'invoke', process = 1, index = 1, time = 1 },
        { type = 'ok', process = 1, index = 2, time = 1.5 },
    }):is_well_formed()
    test:is(ok, false, 'history.is_well_formed(): a fractional time')

    -- A client process must be an integer.
    ok = hist({
        { type = 'invoke', process = 1.5, index = 1, time = 1 },
        { type = 'ok', process = 1.5, index = 2, time = 2 },
    }):is_well_formed()
    test:is(ok, false, 'history.is_well_formed(): a fractional process')

    -- Filtered histories may have sparse indices.
    test:is(hist({
        { type = 'invoke', process = 1, index = 1, time = 1 },
        { type = 'ok', process = 1, index = 3, time = 2 },
    }):is_well_formed(), true,
        'history.is_well_formed(): sparse indices are allowed')

    -- A duplicate index is reported once, not also as a
    -- non-ascending one.
    ok, findings = hist({
        { type = 'invoke', process = 1, index = 1 },
        { type = 'ok', process = 1, index = 1 },
    }):is_well_formed()
    test:is(ok, false, 'history.is_well_formed(): a duplicate index')
    test:unlike(messages(findings), 'not ascending',
        'history.is_well_formed(): no extra ascending error for a duplicate')

    -- A duplicate cdata index is detected as a duplicate.
    ok, findings = hist({
        { type = 'invoke', process = 1, index = ffi.new('int64_t', 1) },
        { type = 'ok', process = 1, index = ffi.new('int64_t', 1) },
    }):is_well_formed()
    test:is(ok, false,
        'history.is_well_formed(): a duplicate cdata index')
    test:like(messages(findings), 'duplicate index',
        'history.is_well_formed(): a duplicate cdata index message')

    -- A sparse history is rejected.
    local sparse = {
        [1] = { type = 'invoke', process = 1, index = 1 },
        [3] = { type = 'ok', process = 1, index = 2 },
    }
    ok = history.is_well_formed(sparse)
    test:is(ok, false, 'history.is_well_formed(): a sparse array')

    -- A non-table history field is rejected by the object form.
    local h = history.new()
    rawset(h, 'history', 'not-a-table')
    ok = h:is_well_formed()
    test:is(ok, false, 'history.is_well_formed(): a non-table ops field')
end)

test:test('op', function(test)
    test:plan(10)
    local op = { f = 'read', value = 10, type = 'invoke' }
    local str = op_lib.to_string(op)
    test:is(str,
        'invoke     read       10        ', "op.to_string() { type = 'invoke'}")

    op = { f = 'read', value = 10, type = 'ok' }
    str = op_lib.to_string(op)
    test:is(str,
        'ok         read       10        ', "op.to_string() { type = 'ok' }")

    op = { f = 'read', value = 10, type = 'fail' }
    str = op_lib.to_string(op)
    test:is(str,
        'fail       read       10        ', "op.to_string() { type = 'fail' }")

    op = { type = 'ok' }
    test:is(op_lib.is_completed(op), true, "op.is_completed() { type = 'ok' }")

    op = { type = 'fail' }
    test:is(op_lib.is_completed(op), true,
        "op.is_completed() { type = 'fail' }")

    op = { type = 'info' }
    test:is(op_lib.is_completed(op), true,
        "op.is_completed() { type = 'info' }")

    op = { type = 'invoke' }
    test:is(op_lib.is_completed(op), false,
        "op.is_completed() { type = 'invoke' }")

    op = { type = 'ok' }
    test:is(op_lib.is_planned(op), false, "op.is_planned() { type = 'ok' }")

    op = { type = 'fail' }
    test:is(op_lib.is_planned(op), false, "op.is_planned() { type = 'fail' }")

    op = { type = 'invoke' }
    test:is(op_lib.is_completed(op), false,
        "op.is_planned() { type = 'invoke' }")
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

    test:is(utils.basename('/home/sergeyb/sources/molly/README.md'),
        'README.md', "utils.basename()")
end)

test:test("utils.is_callable", function(test)
    test:plan(8)

    local string_not_callable = 'str'
    test:is(utils.is_callable(string_not_callable), false,
	        "string is not callable")

    local number_not_callable = 9
    test:is(utils.is_callable(number_not_callable), false,
	        "number is not callable")

    local func_callable = function() end
    test:is(utils.is_callable(func_callable), true, "func is callable")

    local table_callable = setmetatable({}, {
        __call = function() return 'op' end
    })
    test:is(utils.is_callable(table_callable), true, "table is callable")

    local table_not_callable = setmetatable({}, {})
    test:is(utils.is_callable(table_not_callable), false,
	        "table is not callable")

    local userdata_callable = newproxy(true)
    local mt = getmetatable(userdata_callable)
    mt.__call = function() return 'op' end
    test:is(utils.is_callable(userdata_callable), true, "userdata is callable")

    local userdata_not_callable = newproxy(true)
    mt = getmetatable(userdata_not_callable)
    mt.__call = {}
    test:is(utils.is_callable(userdata_not_callable), false,
	        "userdata is callable")

    ffi.cdef[[
        typedef struct
        {
            int data;
        } test_check_struct_t;
    ]]
    ffi.metatype('test_check_struct_t', {
        __call = function(_, key) return key end
    })
    local cdata_callable = ffi.new('test_check_struct_t')
    test:is(utils.is_callable(cdata_callable), true, "cdata is callable")
end)

test:test('utils.is_numeric', function(test)
    test:plan(5)

    test:is(utils.is_numeric(1), true, 'a number is numeric')
    test:is(utils.is_numeric('1'), false, 'a string is not numeric')
    test:is(utils.is_numeric(nil), false, 'nil is not numeric')
    test:is(utils.is_numeric(ffi.new('int64_t', 1)), true,
        'a numeric cdata is numeric')
    test:is(utils.is_numeric(ffi.new('void *')), false,
        'a non-numeric cdata is not numeric')
end)

test:test('utils.is_integer', function(test)
    test:plan(5)

    test:is(utils.is_integer(1), true, 'an integer number is an integer')
    test:is(utils.is_integer(1.5), false,
        'a fractional number is not an integer')
    test:is(utils.is_integer('1'), false, 'a string is not an integer')
    test:is(utils.is_integer(ffi.new('int64_t', 1)), true,
        'an integer cdata is an integer')
    test:is(utils.is_integer(math.huge), false,
        'an infinite number is not an integer')
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
    local _, op, _ = gen(param, state)
    op = type(op) == 'function' and op() or op
    local mop = op.value[1]
    test:is(type(mop), 'table', "tests.rw_register_gen(): mop")
    local mop_key = mop[IDX_MOP_KEY]
    test:is(type(mop_key), 'string', "tests.rw_register_gen(): mop key")
    local mop_type = mop[IDX_MOP_TYPE]
    test:is(mop_type == 'r' or mop_type == 'w', true,
        "tests.rw_register_gen(): mop type")
    local mop_val = mop[IDX_MOP_VAL]
    test:is(type(mop_val) == 'number' or mop_val == json.NULL, true,
        "tests.rw_register_gen(): mop value")
end)

test:test('tests.list_append_gen', function(test)
    test:plan(2)

    local gen, param, state = tests.list_append_gen()
    local _, val = gen(param, state)
    local mop = val.value[1]
    local op_type = mop[OP_TYPE]
    local op_val = mop[OP_VAL]
    test:is(op_type == 'r' or op_type == 'append', true,
        "tests.list_append_gen(): op type")
    test:is(type(op_val) == 'number' or op_val == json.NULL, true,
        "tests.list_append_gen(): op value")
end)

test:test('tests.bank_gen', function(test)
    test:plan(3)

    local num = 5
    local n = tests.bank_gen():take(5):length()
    test:is(n, num, 'tests.bank_gen():length()')

    local gen, param, state = tests.bank_gen()
    local _, val = gen(param, state)

    local op_name = val.f
    test:ok(op_name == 'read' or
            op_name == 'transfer',
            "tests.bank_gen(): op name")
    local op_value = val.v
    test:ok((op_name == 'transfer' and
             (type(op_value.amount) == 'number' or
              type(op_value.from) == 'number' or
              type(op_value.to) == 'number')) or
            (op_name == 'read' and op_value == nil),
            'tests.bank_gen(): op value')
end)

test:test('gen.mix', function(test)
    test:plan(1)

    local tbl = molly.gen.range(1, 5):mix(molly.gen.range(5, 10)):totable()
    test:is(#tbl, 11, 'length of items generated by gen.mix')
end)

test:test('gen.log', function(test)
    test:plan(1)

    local res = molly.gen.iter({1, 2, 3}):log()
    test:is(res, nil, 'gen.log returns nil')
end)

test:test('gen.cycle_times', function(test)
    test:plan(6)

    test:is(type(molly.gen.cycle_times), 'function',
        'gen.cycle_times(): exported function')
    local it = molly.gen.cycle_times(1, molly.gen.duplicate('a'))
    test:is(tostring(it), '<generator>',
        'gen.cycle_times(): returns an iterator')

    local res = {}
    for _, v in molly.gen.cycle_times(
        100, molly.gen.range(1, 3),
        100, molly.gen.duplicate('x')) do
        res[#res + 1] = v
    end
    test:is(table.concat(res, ','), '1,2,3',
        'gen.cycle_times(): stops when a generator is exhausted')

    local gen, param, state = molly.gen.cycle_times(
        0.5, molly.gen.duplicate('a'),
        0.5, molly.gen.duplicate('b')):unwrap()
    local value
    state, value = gen(param, state)
    test:is(value, 'a', 'gen.cycle_times(): first generator')

    local wait = function(t0, total)
        local target = t0 + total * 10^9
        while tonumber(clock.monotonic64()) < target do
            -- Busy wait.
        end
    end
    local t0 = tonumber(clock.monotonic64())
    wait(t0, 0.75)
    state, value = gen(param, state)
    test:is(value, 'b', 'gen.cycle_times(): second generator')
    wait(t0, 1.25)
    value = select(2, gen(param, state))
    test:is(value, 'a', 'gen.cycle_times(): cycles back to first generator')
end)

test:test('gen.flip_flop', function(test)
    test:plan(6)

    test:is(type(molly.gen.flip_flop), 'function',
        'gen.flip_flop(): exported function')
    local it = molly.gen.flip_flop(
        molly.gen.range(1, 2),
        molly.gen.range(3, 4)
    )
    test:is(tostring(it), '<generator>', 'gen.flip_flop(): returns an iterator')

    local collect = function(a, b)
        local res = {}
        for _, v in molly.gen.flip_flop(a, b) do
            res[#res + 1] = v
        end
        return table.concat(res, ',')
    end

    test:is(collect(molly.gen.range(1, 2), molly.gen.range(3, 4)), '1,3,2,4',
        'gen.flip_flop(): alternates and stops when exhausted')
    test:is(collect(molly.gen.duplicate('a'), molly.gen.range(1, 2)),
        'a,1,a,2,a', 'gen.flip_flop(): alternates when second gen is shorter')
    local res = {}
    for _, v in molly.gen.range(1, 2):flip_flop(molly.gen.range(3, 4)) do
        res[#res + 1] = v
    end
    test:is(table.concat(res, ','), '1,3,2,4', 'gen.flip_flop(): method form')
    local ok = pcall(molly.gen.flip_flop, molly.gen.range(1, 2))
    test:is(ok, false, 'gen.flip_flop(): error on a single generator')
end)

for _, backend in ipairs({ 'coroutine', 'fiber' }) do
    test:test('runner (' .. backend .. ')', function(test)
        if not thread_backend_available(backend) then
            test:plan(1)
            test:skip(backend .. ' is not available')
            return
        end

        test:plan(10)

        local workload_opts = {
            client = {},
            generator = {},
        }
        local test_opts = {}

        local ok, err = pcall(runner.run_test, workload_opts, test_opts)
        test:is(ok, false, "runner.run_test(): invalid generator")
        local res = string.find(tostring(err),
            'Generator must have an unwrap method')
        test:isnt(res, nil, "runner.run_test(): err is not nil")

        local single_gen = gen_lib.range(1, 1):map(function(n)
            return { f = 'test', value = n }
        end)
        local opts_with_nodes = {
            nodes = { 'a' },
            thread_type = backend,
        }

        -- A worker returns (false, err) when open() fails.
        local cl = client.new()
        cl.open = function() error('broken open') end
        ok, err = runner.run_test({
            client = cl,
            generator = single_gen,
        }, opts_with_nodes)
        test:ok(not ok, "runner.run_test(): broken open")
        res = string.find(tostring(err), 'broken open')
        test:isnt(res, nil, "runner.run_test(): broken open error")

        -- A worker returns (false, err) when setup() fails.
        cl = client.new()
        cl.setup = function() error('broken setup') end
        ok, err = runner.run_test({
            client = cl,
            generator = single_gen,
        }, opts_with_nodes)
        test:ok(not ok, "runner.run_test(): broken setup")
        res = string.find(tostring(err), 'broken setup')
        test:isnt(res, nil, "runner.run_test(): broken setup error")

        -- A worker returns (false, err) when teardown() fails.
        cl = client.new()
        cl.invoke = function(_self, _op)
            return { type = 'ok', f = 'test' }
        end
        cl.teardown = function() error('broken teardown') end
        ok, err = runner.run_test({
            client = cl,
            generator = single_gen,
        }, opts_with_nodes)
        test:ok(not ok, "runner.run_test(): broken teardown")
        res = string.find(tostring(err), 'broken teardown')
        test:isnt(res, nil, "runner.run_test(): broken teardown error")

        -- A worker panic is propagated to run_test().
        local crash_gen = {
            unwrap = function()
                return function() error('generator boom') end, nil, nil
            end,
        }
        cl = client.new()
        ok, err = runner.run_test({
            client = cl,
            generator = crash_gen,
        }, opts_with_nodes)
        test:ok(not ok, "runner.run_test(): crashed worker")
        res = string.find(tostring(err), 'generator boom')
        test:isnt(res, nil, "runner.run_test(): crashed worker error")
    end)
end

test:test('runner.time_limit', function(test)
    test:plan(3)

    local invocations = 0
    local cl = client.new()
    cl.invoke = function(_self, _op)
        invocations = invocations + 1
        return { type = 'ok', f = 'test' }
    end

    local start_time = clock.monotonic()
    local ok, err = runner.run_test({
        client = cl,
        generator = gen_lib.duplicate({ f = 'test', value = 1 }),
    }, {
        threads = 1,
        nodes = { 'a' },
        time_limit = 0.05,
    })
    local elapsed = clock.monotonic() - start_time

    test:is(ok, true, 'runner.time_limit(): run_test returned ok')
    test:is(err, nil, 'runner.time_limit(): err is nil')
    test:ok(invocations > 0 and elapsed < 5,
            'runner.time_limit(): generator is stopped by time limit')
end)

test:test('runner.summary', function(test)
    test:plan(4)

    local history = {
        ops_completed = function() return 10 end,
        ops_planned = function() return 10 end,
    }

    local stats = runner.internal.summary(0, history)
    test:is(stats.ops_planned, 10, 'runner.summary(): planned requests')
    test:is(stats.ops_completed, 10,
        'runner.summary(): completed requests')
    test:is(stats.rps, nil,
        'runner.summary(): no RPS on a zero duration')

    stats = runner.internal.summary(2, history)
    test:is(stats.rps, 5, 'runner.summary(): RPS is based on duration')
end)

test:test('runner.checkers', function(test)
    test:plan(3)

    test:is(checkers.workload_opts({ client = {}, generator = {} }), true,
            'runner.checkers(): checker is optional')
    test:is(checkers.workload_opts({
        client = {},
        generator = {},
        checker = {},
    }), true, 'runner.checkers(): checker is a table')
    test:is(checkers.workload_opts({
        client = {},
        generator = {},
        checker = 'x',
    }), false, 'runner.checkers(): checker must be a table')
end)

for _, backend in ipairs({ 'coroutine', 'fiber' }) do
    test:test('client.invoke_fail (' .. backend .. ')', function(test)
        if not thread_backend_available(backend) then
            test:plan(1)
            test:skip(backend .. ' is not available')
            return
        end

        test:plan(5)

        local cl = client.new()
        cl.invoke = function(_self, _op)
            error('invoke boom')
        end

        local hist = history.new()
        local pool = threadpool.new(backend, 1)
        local ok = pool:start(client.run, {
            client = cl,
            gen = gen_lib.range(1, 1):map(function(n)
                return { f = 'test', value = n }
            end),
            history = hist,
            nodes = { 'a' },
        })
        test:is(ok, true, 'client.invoke_fail(): run_client returned ok')

        local ops = hist.history
        test:is(#ops, 2,
            'client.invoke_fail(): history has invoke and info ops')
        test:is(ops[1].type, 'invoke',
            'client.invoke_fail(): invoke op is recorded')
        test:is(ops[2].type, 'info',
            'client.invoke_fail(): info op is recorded')
        test:isnt(string.find(ops[2].error, 'invoke boom'), nil,
            'client.invoke_fail(): error message is recorded')
    end)
end

for _, backend in ipairs({ 'coroutine', 'fiber' }) do
    test:test('client.reopen (' .. backend .. ')', function(test)
        if not thread_backend_available(backend) then
            test:plan(1)
            test:skip(backend .. ' is not available')
            return
        end

        test:plan(9)

        local opened, closed = 0, 0
        local crashed = false
        local cl = client.new()
        cl.open = function(_self, _addr, _client_data)
            opened = opened + 1
            return true
        end
        cl.setup = function(_self, _client_data)
            return true
        end
        cl.close = function(_self, _client_data)
            closed = closed + 1
            return true
        end
        cl.invoke = function(_self, op)
            if not crashed then
                crashed = true
                error('invoke boom')
            end
            return { type = 'ok', f = op.f }
        end

        local hist = history.new()
        local pool = threadpool.new(backend, 1)
        local ok = pool:start(client.run, {
            client = cl,
            gen = gen_lib.range(1, 3):map(function(n)
                return { f = 'test', value = n }
            end),
            history = hist,
            nodes = { 'a' },
        })
        test:is(ok, true, 'client.reopen(): run_client returned ok')

        local ops = hist.history
        test:is(#ops, 6, 'client.reopen(): history has six ops')
        test:is(ops[2].type, 'info',
            'client.reopen(): a crash is recorded as info')
        test:is(ops[1].process, 1, 'client.reopen(): crashed process id')
        test:is(ops[2].process, 1,
            'client.reopen(): completion keeps the crashed process id')
        test:is(ops[3].process, 2,
            'client.reopen(): the next operation has a new process id')
        test:is(ops[4].type, 'ok',
            'client.reopen(): the next operation succeeds')
        test:is(opened, 2, 'client.reopen(): the client is reopened')
        test:is(closed, 2,
            'client.reopen(): the client is closed on reopen and at the end')
    end)
end

------------------------
-- Integration tests  --
------------------------

local test_dict = {}

local client_dict = client.new()

client_dict.invoke = function(_self, op)
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

-- Run a test that generates random read and write operations for
-- Lua dictionary.
local run_test_dict = function(thread_type)
    if utils.is_tarantool() == false and thread_type == 'fiber' then
        return false
    end

    local test_options = {
        create_reports = true,
        thread_type = thread_type,
        threads = 5,
        -- Required for better code coverage.
        nodes = { 'a', 'b', 'c' },
    }
    local ok, err = runner.run_test({
        client = client_dict,
        generator = tests.rw_register_gen():take(100)
    }, test_options)

    assert(err == nil, "run_test_dict: err is not nil")
    assert(ok, "run_test_dict: ok is not true")

    if ok == true and test_options.create_reports == true then
        assert(helpers.file_exists('history.txt'), "history.txt does not exist")
        assert(helpers.file_exists('history.json'),
            "history.json does not exist")

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
    local fiber_pool
    ok, fiber_pool = pcall(threadpool.new, 'fiber', 1)
    local res_tarantool = ok == true and
        type(fiber_pool) == 'table' and
        utils.is_tarantool() == true
    local res_luajit = ok == false and utils.is_tarantool() == false and
        string.find(fiber_pool, 'No thread library with type "fiber"') ~= nil
    test:is(res_luajit or res_tarantool, true, "threadpool.new('fiber'): type")

    local err
    ok, err = pcall(threadpool.new, 'xxx', 1)
    test:is(ok, false, "threadpool.new('xxx'): ok is true")
    res = string.find(tostring(err), 'No thread library with type "xxx"')
    test:isnt(res, nil, "threadpool.new('xxx'): error is correct")
end)

for _, backend in ipairs({ 'coroutine', 'fiber' }) do
    test:test('threadpool.args (' .. backend .. ')', function(test)
        if not thread_backend_available(backend) then
            test:plan(1)
            test:skip(backend .. ' is not available')
            return
        end

        test:plan(3)

        local seen = {}
        local pool = threadpool.new(backend, 1)
        local function worker(id, opts)
            seen = { id = id, opts = opts }
            return true
        end
        local ok = pool:start(worker, { marker = 'x' })
        test:is(ok, true, 'threadpool.args(): start returned ok')
        test:is(seen.id, 1, 'threadpool.args(): thread_id is passed')
        test:is(seen.opts.marker, 'x',
            'threadpool.args(): worker arguments are passed')
    end)
end

for _, backend in ipairs({ 'coroutine', 'fiber' }) do
    test:test('threadpool.worker_error (' .. backend .. ')', function(test)
        if not thread_backend_available(backend) then
            test:plan(1)
            test:skip(backend .. ' is not available')
            return
        end

        test:plan(2)

        local pool = threadpool.new(backend, 1)
        local ok, err = pool:start(function() error('worker boom') end, {})
        test:is(ok, nil, 'threadpool.worker_error(): start returned nil')
        local res = string.find(tostring(err), 'worker boom')
        test:isnt(res, nil, 'threadpool.worker_error(): error is propagated')
    end)
end

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
-- Thread sync tests  --
------------------------

local function sync_subtest(backend, kind, checks_fn)
    test:test('sync.' .. kind .. ' (' .. backend .. ')', function(test)
        if not thread_backend_available(backend) then
            test:plan(1)
            test:skip(backend .. ' is not available')
            return
        end

        local ok, checks = pcall(checks_fn, backend)
        if not ok then
            test:plan(1)
            test:fail('sync.' .. kind .. ' (' .. backend ..
                ') raised an error: ' .. tostring(checks))
            return
        end

        test:plan(#checks)
        for _, check in ipairs(checks) do
            test:is(check.ok, true, check.name)
        end
    end)
end

local sync_barrier = function(backend)
    local N = 5
    local barrier = thread.barrier_new(N)
    local mutex = thread.mutex_new()
    local counter = 0
    local order = {}

    local pool = threadpool.new(backend, N)
    local ok = pool:start(function(thread_id, opts)
        opts.barrier:wait()
        opts.mutex:lock()
        counter = counter + 1
        order[#order + 1] = thread_id .. '-r1'
        opts.mutex:unlock()
        opts.barrier:wait()
        opts.mutex:lock()
        counter = counter + 1
        order[#order + 1] = thread_id .. '-r2'
        opts.mutex:unlock()
        return true
    end, { barrier = barrier, mutex = mutex })

    local max_r1, min_r2 = 0, math.huge
    for idx, s in ipairs(order) do
        if string.find(s, 'r1') then
            max_r1 = math.max(max_r1, idx)
        else
            min_r2 = math.min(min_r2, idx)
        end
    end

    return {
        { ok = ok == true, name = 'pool with a barrier completes' },
        { ok = counter == 2 * N,
          name = 'a barrier releases all workers every round' },
        { ok = #order == 2 * N and max_r1 < min_r2,
          name = 'a barrier separates rounds of workers' },
    }
end

local sync_mutex = function(backend)
    local N = 5
    local mutex = thread.mutex_new()
    local counter = 0

    local pool = threadpool.new(backend, N)
    local ok = pool:start(function(_thread_id, opts)
        for _ = 1, 10 do
            opts.mutex:lock()
            counter = counter + 1
            opts.mutex:unlock()
        end
        return true
    end, { mutex = mutex })

    mutex = thread.mutex_new()
    local unlocked_err = pcall(function()
        mutex:unlock()
    end)

    return {
        { ok = ok == true, name = 'pool with a mutex completes' },
        { ok = counter == 10 * N,
          name = 'a mutex serializes critical sections' },
        { ok = mutex:trylock() == true,
          name = 'trylock() locks an unlocked mutex' },
        { ok = mutex:trylock() == false,
          name = 'trylock() reports a locked mutex' },
        { ok = unlocked_err == false,
          name = 'unlock() of an unlocked mutex raises an error' },
    }
end

local sync_wg = function(backend)
    local N = 5
    local wg = thread.wg_new()
    local waiter_done = false
    wg:add(N - 1)

    local pool = threadpool.new(backend, N)
    local ok = pool:start(function(thread_id, opts)
        if thread_id == 1 then
            opts.wg:wait()
            waiter_done = true
            return true
        end
        opts.wg:done()
        return true
    end, { wg = wg })

    return {
        { ok = ok == true, name = 'pool with a wait group completes' },
        { ok = waiter_done == true,
          name = 'wait() returns when the counter is zero' },
    }
end

local sync_failstop = function(backend)
    local N = 5
    local barrier = thread.barrier_new(N)
    local finished = {}

    local pool = threadpool.new(backend, N)
    local ok, err = pool:start(function(thread_id, opts)
        if thread_id == N then
            error('boom')
        end
        opts.barrier:wait()
        finished[thread_id] = true
        return true
    end, { barrier = barrier })

    local others_done = false
    for i = 1, N - 1 do
        if finished[i] == true then
            others_done = true
        end
    end

    return {
        { ok = ok == nil and err ~= nil and
              string.find(tostring(err), 'boom') ~= nil,
          name = 'a failed worker makes the pool return an error' },
        { ok = others_done == false,
          name = 'the rest of workers are cancelled after a failure' },
    }
end

for _, backend in ipairs({ 'fiber', 'coroutine' }) do
    sync_subtest(backend, 'barrier', sync_barrier)
    sync_subtest(backend, 'mutex', sync_mutex)
    sync_subtest(backend, 'wg', sync_wg)
    sync_subtest(backend, 'failstop', sync_failstop)
end

-- A client that records stages of its lifecycle into a shared
-- log.
local stage_client = function(log)
    local cl = client.new()
    cl.open = function(_self, _addr, _client_data)
        log[#log + 1] = 'open'
        return true
    end
    cl.setup = function(_self, _client_data)
        log[#log + 1] = 'setup'
        return true
    end
    cl.invoke = function(_self, _op, _client_data)
        log[#log + 1] = 'invoke'
        return { type = 'ok', f = 'test' }
    end
    cl.teardown = function(_self, _client_data)
        log[#log + 1] = 'teardown'
        return true
    end
    cl.close = function(_self, _client_data)
        log[#log + 1] = 'close'
        return true
    end
    return cl
end

-- A client whose chosen stage raises an error. Used to check that
-- a failed stage aborts the rest of the pool instead of leaving
-- threads hanging on a barrier.
local stage_failure_client = function(stage)
    local cl = client.new()
    cl.invoke = function(_self, _op, _client_data)
        return { type = 'ok', f = 'test' }
    end
    cl[stage] = function()
        error('broken ' .. stage)
    end
    return cl
end

local function count_phase(log, phase)
    local n = 0
    for _, marker in ipairs(log) do
        if marker == phase then
            n = n + 1
        end
    end
    return n
end

local function marker_bounds(log, phase)
    local first, last
    for idx, marker in ipairs(log) do
        if marker == phase then
            if first == nil then
                first = idx
            end
            last = idx
        end
    end
    return first, last
end

-- Verify that run_client() synchronizes stages with barriers:
-- every thread opens and sets up before any operation, and tears
-- down only after all threads finished operations.
local sync_stages = function(backend)
    local N = 3
    local total_ops = 30
    local generator = function()
        return gen_lib.range(1, total_ops):map(function(n)
            return { f = 'test', value = n }
        end)
    end

    local log = {}
    local cl = stage_client(log)
    local ok = runner.run_test({
        client = cl,
        generator = generator(),
    }, {
        threads = N,
        thread_type = backend,
        nodes = { 'a' },
    })

    local _, open_l = marker_bounds(log, 'open')
    local setup_f, setup_l = marker_bounds(log, 'setup')
    local invoke_f, invoke_l = marker_bounds(log, 'invoke')
    local teardown_f = marker_bounds(log, 'teardown')

    -- A failed stage must abort the run on every thread backend
    -- instead of leaving other threads hanging on a barrier.
    local failed = {}
    for _, stage in ipairs({ 'open', 'setup', 'teardown' }) do
        local okr, errr = runner.run_test({
            client = stage_failure_client(stage),
            generator = generator(),
        }, {
            threads = N,
            thread_type = backend,
            nodes = { 'a' },
        })
        failed[stage] = okr == nil and errr ~= nil and
            string.find(tostring(errr), 'broken ' .. stage) ~= nil
    end

    return {
        { ok = ok == true,
          name = 'run_test with synchronized stages completed' },
        { ok = count_phase(log, 'open') == N and
              count_phase(log, 'setup') == N and
              count_phase(log, 'teardown') == N and
              count_phase(log, 'close') == N,
          name = 'each thread ran open/setup/teardown/close once' },
        { ok = count_phase(log, 'invoke') == total_ops,
          name = 'each generated operation was invoked once' },
        { ok = open_l ~= nil and setup_f ~= nil and open_l < setup_f,
          name = 'threads open a connection before any setup' },
        { ok = setup_l ~= nil and invoke_f ~= nil and setup_l < invoke_f,
          name = 'threads set up the DB before any operation' },
        { ok = invoke_l ~= nil and teardown_f ~= nil and
              invoke_l < teardown_f,
          name = 'threads finish operations before any teardown' },
        { ok = failed.open == true,
          name = 'a broken open aborts a run with several threads' },
        { ok = failed.setup == true,
          name = 'a broken setup aborts a run with several threads' },
        { ok = failed.teardown == true,
          name = 'a broken teardown aborts a run with several threads' },
    }
end

local function stages_subtest(backend, checks_fn)
    test:test('stages (' .. backend .. ')', function(test)
        if not thread_backend_available(backend) then
            test:plan(1)
            test:skip(backend .. ' is not available')
            return
        end

        local ok, checks = pcall(checks_fn, backend)
        if not ok then
            test:plan(1)
            test:fail('stages (' .. backend .. ') raised an error: ' ..
                tostring(checks))
            return
        end

        test:plan(#checks)
        for _, check in ipairs(checks) do
            test:is(check.ok, true, check.name)
        end
    end)
end

stages_subtest('fiber', sync_stages)
stages_subtest('coroutine', sync_stages)

------------------------
---- Run the tests  ----
------------------------

require('test.coverage').shutdown()

os.exit(test:check() == true and 0 or 1)
