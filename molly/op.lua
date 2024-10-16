---- Module with helpers that processes operations.
-- @module molly.op
--
-- An operation is a transition from state to state. For instance, a
-- single-variable system might have operations like read and write, which get
-- and set the value of that variable, respectively. A counter might have
-- operations like increments, decrements, and reads. An SQL store might have
-- operations like selects and updates.
--
-- An observed history should be a list of operations in real-time order, where
-- each operation is a map of the form:
--
--     {
--         type    One of `invoke`, `ok`, `info`, `fail`.
--         process A logical identifier for a single thread of execution.
--         value   A transaction; structure and semantics vary.
--     }
--
-- Each process should perform alternating `invoke` and `ok`, `info`, `fail`
-- operations. `ok` indicates the operation definitely committed. `fail`
-- indicates it definitely did not occur - e.g. it was aborted, was never
-- submitted to the database, etc. `info` indicates an indeterminate state; the
-- transaction may or may not have taken place. After an `info`, a process may
-- not perform another operation; the invocation remains open for the rest of
-- the history.
--
-- We define each operation as a table or a callable object that return
-- a table, that contains following keys:
--
--  - state, can be nil (invoke), true (ok) or false (fail);
--  - f is an action defined in a test, for example 'transfer', 'read' or
--  'write';
--  - v is a valued defined in a test, usually it is generated automatically;
--
--  For example an operation with 'read' action, value is 'nil' because it is
--  unknown before invoking of operation:
--
--    {
--        f = 'read',
--        value = nil,
--    }
--
--    4  ok       read       {0 5, 1 10, 2 12, 8 10, 9 17}
--    4  invoke   read       nil
--    3  ok       read       {0 5, 1 9, 2 12, 3 10, 4 11}
--    3  invoke   read       nil
--
--  or operation with 'transfer' action for test that transfers money between
--  accounts:
--
--    {
--        f = 'transfer',
--        value = {
--            from = math.random(1, 10),
--            to = math.random(1, 10),
--            amount = math.random(1, 100),
--        }
--    }
--
--    3  ok       transfer   {from = 8, to = 2, amount = 3}
--    0  ok       transfer   {from = 1, to = 9, amount = 1}
--    0  invoke   transfer   {from = 3, to = 9, amount = 5}

local dev_checks = require('molly.dev_checks')
local pprint = require('molly.json').encode

-- Define whether operation is in planned state.
-- @table op Operation.
-- @return boolean
--
-- @function is_planned
local function is_planned(op)
    dev_checks('<operation>|table')
    return op.type == 'invoke'
end

-- Define whether operation is in completed state.
-- @table op Operation.
-- @return boolean
--
-- @function is_completed
local function is_completed(op)
    dev_checks('<operation>|table')
    return op.type == 'ok' or
           op.type == 'fail'
end

-- Get a string representation of operation.
-- @table op Operation.
-- @return string
--
-- @function to_string
local function to_string(op)
    dev_checks('<operation>|table')
    return ('%-10s %-10s %-10s'):format(op.type, op.f, pprint(op.value))
end

return {
    is_planned = is_planned,
    is_completed = is_completed,
    to_string = to_string,
}
