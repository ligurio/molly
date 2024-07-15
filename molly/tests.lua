---- Module with test generators and checkers.
-- @module molly.tests
--
--### List-Append
--
-- list-append operations are either appends or reads
--
-- Detects cycles in histories where operations are transactions over named
-- lists lists, and operations are either appends or reads.
--
-- The *append* test models the database as a collection of named lists,
-- and performs transactions comprised of read and append operations. A
-- read returns the value of a particular list, and an append adds a single
-- unique element to the end of a particular list. We derive ordering
-- dependencies between these transactions, and search for cycles in that
-- dependency graph to identify consistency anomalies.
--
-- In terms of Molly, values in operation are lists of integers. Each operation
-- performs a transaction, comprised of micro-operations which are either reads
-- of some value (returning the entire list) or appends (adding a single number
-- to whatever the present value of the given list is). We detect cycles in
-- these transactions using Elle's cycle-detection system.
--
-- Generator `molly.tests.list_append_gen` produces an operations
-- compatible with Molly:
--
--     { index = 2, type = "invoke", value = {{ "append", 255, 8 } { "r", 253, null }}}
--     { index = 3, type = "ok",     value = {{ "append", 255, 8 } { "r", 253, { 1, 3, 4 }}}}
--     { index = 4, type = "invoke", value = {{ "append", 256, 4 } { "r", 255, null } { "r", 256, nil } { "r", 253, null }}}
--     { index = 5, type = "ok",     value = {{ "append", 256, 4 } { "r", 255, { 2, 3, 4, 5, 8 }} { "r", 256, { 1, 2, 4 }} {{ "r", 253, { 1, 3, 4 }}}}
--     { index = 6, type = "invoke", value = {{ "append", 250, 10 } { "r", 253, null }{ "r", 255, null } { "append", 256, 3 }}}
--
-- A partial test, including a generator and checker. You'll need to provide a
-- client which can understand operations of the form:
--
--     { type = "invoke", f = "txn", value = {{ "r", 3, null } { "append", 3, 2 } { "r", 3, null }}}
--
-- and return completions like:
--
--     { type = "invoke", f = "txn", value = {{ "r", 3, { 1 }} { "append", 3, 2 } { "r", 3, { 1, 2 }}}}
--
-- where the key `3` identifies some list, whose value is initially `[1]`, and
-- becomes `[1 2]`.
--
-- Lists are encoded as rows in a table; key names are table names, and the set
-- of all rows determines the list contents.
--
-- This test requires a way to order table contents.
--
--### RW Register
--
-- Generator produces concurrent atomic updates to a shared register. Writes
-- are assumed to be unique, but this is the only constraint.
--
-- Operations are of two forms:
--
--     { "r", "x", 1 } denotes a read of `x` observing the value 1.
--     { "w", "x", 2 } denotes a write of `x`, settings its value to 2.
--
-- Example of history:
--
--     { type = "invoke", f = "txn", value = {{ "w", "x", 1 }},   process = 0, index = 1}
--     { type = "ok",     f = "txn", value = {{ "w", "x", 1 }},   process = 0, index = 2}
--     { type = "invoke", f = "txn", value = {{ "r", "x", null }}, process = 0, index = 3}
--     { type = "ok",     f = "txn", value = {{ "r", "x", 2 }},   process = 0, index = 4}
--
-- Note that in Lua associative array is an array that can be indexed not only
-- with numbers, but also with strings or any other value of the language,
-- except nil. Null values in Lua tables are represented as JSON null
-- (`json.NULL`, a Lua `lightuserdata` NULL pointer) is provided for
-- comparison.
--
--### CAS-Register
--
-- Generator produces concurrent atomic updates to a shared
-- register. Writes are assumed to be unique, but this is the only
-- constraint.
--
-- Operations are of three forms:
--
--     { "r", "x", 1 } denotes a read of `x` observing the value 1.
--     { "w", "x", 2 } denotes a write of `x`, settings its value to 2.
--     { "cas", "x", 2 } denotes a CAS of `x`, settings its value to 2.
--
-- Example of history:
--
--     { type = "invoke", f = "cas", value = { 1, 5 },  process = 0, index = 1}
--     { type = "ok",     f = "fail", value = { 1, 5 }, process = 0, index = 2}
--     { type = "invoke", f = "write", value = { 2 },   process = 0, index = 3}
--     { type = "ok",     f = "write", value = { 2 },   process = 0, index = 4}
--
--### Bank
--
-- Generator produces updates to a set of bank accounts and transfers
-- money between them at random, ensuring that no account goes negative.
--
-- Example of a history:
--
--     {:type :invoke, :f :transfer, :process 0, :time 12613722542, :index 34, :value {:from 1, :to 0, :amount 5}}
--     {:type :fail,   :f :transfer, :process 0, :time 12686176735, :index 35, :value {:from 1, :to 0, :amount 5}}
--     {:type :invoke, :f :read,     :process 0, :time 12686563291, :index 36}
--     {:type :ok,     :f :read,     :process 0, :time 12799165489, :index 37, :value {0 97, 1 0, 2 0, 3 0, 4 0, 5 3, 6 0, 7 0, 8 0, 9 0}}
--

local math = require('math')

local dev_checks = require('molly.dev_checks')
local gen_lib = require('molly.gen')
local json = require('molly.json')

-- Function that describes a 'read' operation.
local function op_r()
    return setmetatable({
        f = 'txn',
        value = {{
            'r',
            'x',
            json.NULL,
        }},
    }, {
        __type = '<operation>',
        __tostring = function(self)
            return '<read>'
        end,
    })
end

-- Function that describes a 'write' operation.
local function op_w()
    return setmetatable({
        f = 'txn',
        value = {{
            'w',
            'x',
            math.random(1, 100),
        }}
    }, {
        __type = '<operation>',
        __tostring = function(self)
            return '<write>'
        end,
    })
end

--- Write/Read operations generator.
--
-- @usage
--
-- > log = require('log')
-- > tests = require('molly.tests')
-- > for _it, v in tests.rw_register_gen() do log.info(v()) end
-- {"f":"txn","value":[["r","x",null]]}
-- {"f":"txn","value":[["w","x",58]]}
-- {"f":"txn","value":[["r","x",null]]}
-- {"f":"txn","value":[["w","x",80]]}
-- {"f":"txn","value":[["r","x",null]]}
-- {"f":"txn","value":[["w","x",46]]}
-- {"f":"txn","value":[["r","x",null]]}
-- {"f":"txn","value":[["w","x",19]]}
-- {"f":"txn","value":[["r","x",null]]}
-- {"f":"txn","value":[["w","x",66]]}
-- ---
-- ...
--
-- @return an iterator
--
-- @function rw_register_gen
local function rw_register_gen()
    return gen_lib.cycle(gen_lib.iter({ op_r, op_w }))
end

-- Function that describes a 'read' operation.
local function cas_op_r()
    return setmetatable({
        f = 'read',
        value = {
            json.NULL,
        },
    }, {
        __type = '<operation>',
        __tostring = function(self)
            return '<read>'
        end,
    })
end

-- Function that describes a 'write' operation.
local function cas_op_w()
    return setmetatable({
        f = 'write',
        value = {
            math.random(1, 100),
        }
    }, {
        __type = '<operation>',
        __tostring = function(self)
            return '<write>'
        end,
    })
end

-- Function that describes a 'cas' operation.
local function cas_op_cas()
    return setmetatable({
        f = 'cas',
        value = {
            math.random(1, 100),
            math.random(1, 100),
        }
    }, {
        __type = '<operation>',
        __tostring = function(self)
            return '<cas>'
        end,
    })
end

--- CAS (Compare-And-Set) operations generator.
--
-- @usage
--
-- > log = require('log')
-- > tests = require('molly.tests')
-- > for _it, v in tests.cas_register_gen() do log.info(v()) end
-- {"f":"read","value":[null]}
-- {"f":"write","value":[80]}
-- {"f":"cas","value":[70,60]}
-- {"f":"read","value":[null]}
-- {"f":"write","value":[76]}
-- {"f":"cas","value":[9,67]}
-- {"f":"read","value":[null]}
-- {"f":"write","value":[34]}
-- {"f":"cas","value":[74,43]}
-- {"f":"read","value":[null]}
-- ---
-- ...
--
-- @return an iterator
--
-- @function cas_register_gen
local function cas_register_gen()
    return gen_lib.cycle(gen_lib.iter({ cas_op_r, cas_op_w, cas_op_cas }))
end

-- Function that describes a 'list' micro operation.
local function mop_list(key_count)
    return {
        'r',
        math.random(key_count),
        json.NULL,
    }
end

local function counter()
    local i = 0
    return function()
        i = i + 1
        return i
    end
end

local c = counter()

-- Function that describes an 'append' micro operation.
local function mop_append(key_count)
    return {
        'append',
        math.random(key_count),
        c(),
    }
end

local function list_append_op(param)
    local mops = {}
    for _ = 1, math.random(param.min_txn_len, param.max_txn_len) do
        if math.random(1, 2) == 1 then
            table.insert(mops, mop_list(param.key_count))
        else
            table.insert(mops, mop_append(param.key_count))
        end
    end
    return 0, setmetatable({
        f = 'txn',
        value = mops,
    }, {
        __type = '<operation>',
        __tostring = function(self)
            return '<list-append>'
        end,
    })
end

--- List-Append operations generator.
--
-- A generator for operations where values are transactions made up of reads
-- and appends to various integer keys.
-- @table[opt] opts Table with options.
-- @number[opt] opts.key_count Number of distinct keys at any point. Default is
-- 3.
-- @number[opt] opts.min_txn_len Minimum number of operations per txn. Default
-- is 1.
-- @number[opt] opts.max_txn_len Maximum number of operations per txn. Default
-- is 2.
-- @number[opt] opts.max_writes_per_key Maximum number of operations per key.
-- Default is 32.
-- @usage
--
-- > log = require('log')
-- > tests = require('molly.tests')
-- > for _it, v in tests.list_append_gen() do log.info(v()) end
-- {"f":"txn","value":[["r",3,null]]}
-- {"f":"txn","value":[["append",3,1]]}
-- {"f":"txn","value":[["r",2,null]]}
-- {"f":"txn","value":[["append",3,2]]}
-- {"f":"txn","value":[["r",1,null]]}
-- {"f":"txn","value":[["append",2,3]]}
-- {"f":"txn","value":[["r",2,null]]}
-- {"f":"txn","value":[["append",3,4]]}
-- {"f":"txn","value":[["r",2,null]]}
-- {"f":"txn","value":[["append",2,5]]}
-- ---
-- ...
--
-- @return an iterator
--
-- @function list_append_gen
local function list_append_gen(opts)
    dev_checks('?table')

    opts = opts or {}
    local param = {}
    param.key_count = opts.key_count or 3
    param.min_txn_len = opts.min_txn_len or 1
    param.max_txn_len = opts.max_txn_len or 2
    param.max_writes_per_key = opts.max_writes_per_key or 32

    assert(type(param.max_txn_len) == 'number', 'max_txn_len must be a number')
    assert(type(param.min_txn_len) == 'number', 'min_txn_len must be a number')
    assert(type(param.max_writes_per_key) == 'number',
           'max_writes_per_key must be a number')
    assert(param.min_txn_len < param.max_txn_len,
           'max_txn_len must be bigger than min_txn_len')

    return gen_lib.wrap(list_append_op, param, 0)
end

local function bank_op_read()
    return {
        f = 'read',
        value = nil,
    }
end

local function bank_op_transfer(accounts, max_transfer)
    return function()
        return {
            f = 'transfer',
            value = {
                from = math.random(1, accounts),
                to = math.random(1, accounts),
                amount = math.random(1, max_transfer),
            }
        }
    end
end

--- A bank operations generator.
--
-- A generator of operations that simulate transfers between bank
-- accounts, checker should verify that reads always show the same
-- balance.
-- @table[opt] opts Table with options.
-- @number[opt] opts.accounts A collection of account identifiers.
-- @number[opt] opts.max_transfer A largest transfer the test will
-- try to execute.
-- @usage
--
-- > log = require('log')
-- > tests = require('molly.tests')
-- > tests.bank_gen():map(function(op) return type(op) == 'function' and op() or op end):take(10):each(log.info)
-- {"f":"read"}
-- {"f":"transfer","value":{"amount":2,"from":8,"to":7}}
-- {"f":"read"}
-- {"f":"transfer","value":{"amount":2,"from":8,"to":1}}
-- {"f":"read"}
-- {"f":"transfer","value":{"amount":1,"from":4,"to":8}}
-- {"f":"read"}
-- {"f":"transfer","value":{"amount":1,"from":6,"to":2}}
-- {"f":"read"}
-- {"f":"transfer","value":{"amount":1,"from":10,"to":8}}
-- ---
-- ...
--
-- @return an iterator
--
-- @function bank_gen
local function bank_gen(opts)
    dev_checks('?table')

    opts = opts or {}
    local param = {}
    param.accounts = opts.accounts or 10
    param.max_transfer = opts.max_transfer or 2

    assert(type(param.accounts) == 'number', 'accounts must be a number')
    assert(type(param.max_transfer) == 'number',
           'max_transfer must be a number')

    return gen_lib.cycle(gen_lib.iter({
        bank_op_read(),
        bank_op_transfer(param.accounts, param.max_transfer),
    }))
end

return {
    bank_gen = bank_gen,
    list_append_gen = list_append_gen,
    rw_register_gen = rw_register_gen,
    cas_register_gen = cas_register_gen,
}
