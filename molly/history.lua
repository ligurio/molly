---- Module with functions that processes history of operations.
-- @module molly.history

local dev_checks = require('molly.dev_checks')
local gen = require('molly.gen')
local json = require('molly.json')
local op = require('molly.op')
local utils = require('molly.utils')

-- The `:type` must be one of `:invoke`, `:ok`, `:info` or
-- `:fail`. See "Operation Structure" in the Jepsen history
-- documentation:
-- https://github.com/jepsen-io/history#operation-structure
local function is_type(t)
    return t == 'invoke' or t == 'ok' or t == 'info' or t == 'fail'
end

-- Create a description of a rule violation found in a history.
local function finding(severity, message, op_item)
    return {
        severity = severity,
        message = message,
        index = op_item ~= nil and op_item.index or nil,
        process = op_item ~= nil and op_item.process or nil,
    }
end

local function add_error(findings, message, op_item)
    table.insert(findings, finding('error', message, op_item))
end

local function add_warning(findings, message, op_item)
    table.insert(findings, finding('warning', message, op_item))
end

local mt

-- Check a single operation and update per-process, index and time
-- state accumulated while walking the history.
local function check_op(op_item, findings, state, position)
    if type(op_item) ~= 'table' then
        add_error(findings, ('operation at position %d is not a table: %s')
            :format(position, tostring(op_item)), nil)
        return
    end

    if not is_type(op_item.type) then
        add_error(findings, ('invalid operation type "%s"'):format(
            tostring(op_item.type)), op_item)
        return
    end

    local process = op_item.process

    -- Every operation belongs to a process; the field is
    -- required. See #operation-structure.
    if process == nil then
        add_error(findings, 'operation has no process', op_item)

    -- Nemeses have string process identifiers and use `:info`
    -- for both invocation and completion. Such processes do not
    -- follow the client lifecycle below.
    -- See #operation-structure.
    elseif type(process) == 'string' then
        if op_item.type ~= 'info' then
            add_error(findings,
                'nemesis operation must be of type info', op_item)
        end
    elseif type(process) ~= 'number' then
        add_error(findings,
            'process is not a number or a string', op_item)
    else
        -- Processes are logically single-threaded and run one
        -- thing at a time, so an `invoke` and its completion
        -- alternate within a process.
        -- See #operation-semantics.
        if op_item.type == 'invoke' then
            -- If a process crashes (an `invoke` followed by an
            -- `info`), it can never invoke an operation again.
            -- See #operation-semantics.
            if state.crashed[process] then
                add_error(findings, ('process %s invoked after info')
                    :format(tostring(process)), op_item)
            elseif state.pending[process] then
                add_error(findings, ('process %s invoked twice')
                    :format(tostring(process)), op_item)
            else
                state.pending[process] = op_item
            end
        else
            if not state.pending[process] then
                add_error(findings,
                    ('process %s completed without invoke')
                    :format(tostring(process)), op_item)
            end
            state.pending[process] = nil
            if op_item.type == 'info' then
                state.crashed[process] = true
            end
        end
    end

    -- `:index` is a unique, monotonically ascending integer. It
    -- may be omitted, so the check is skipped when the field is
    -- absent.
    -- https://github.com/jepsen-io/history#operation-structure
    if op_item.index ~= nil then
        if not utils.is_integer(op_item.index) then
            add_error(findings, ('index is not an integer: %s'):format(
                tostring(op_item.index)), op_item)
        else
            local index_key = tonumber(op_item.index)
            if state.seen_index[index_key] then
                add_error(findings, ('duplicate index %s'):format(
                    tostring(op_item.index)), op_item)
            elseif state.last_index ~= nil and
                   op_item.index <= state.last_index then
                add_error(findings, ('index %s is not ascending'):format(
                    tostring(op_item.index)), op_item)
            end
            state.seen_index[index_key] = true
            if state.last_index == nil or
                    op_item.index > state.last_index then
                state.last_index = op_item.index
            end
        end
    end

    -- `:time` is the time since the start of the test in
    -- nanoseconds; the history is totally ordered. A
    -- non-monotonic time is a warning, not an error.
    -- https://github.com/jepsen-io/history#operation-structure
    if op_item.time ~= nil then
        if not utils.is_numeric(op_item.time) then
            add_error(findings, ('time is not a number: %s'):format(
                tostring(op_item.time)), op_item)
        else
            if state.last_time ~= nil and
                    op_item.time < state.last_time then
                add_warning(findings, ('time %s is not monotonic'):format(
                    tostring(op_item.time)), op_item)
            end
            state.last_time = op_item.time
        end
    end
end

--- Check whether a history is well-formed.
--
-- Accepts a `molly.history` object (as a method) or a plain array
-- of operations (as a function) and verifies the structure and
-- semantics from the Jepsen history documentation.
--
-- Rules checked (severity in parentheses):
--
-- - the history (or the `history` field of an object) is a
--   table (error);
-- - every operation is a table (error);
-- - `type` is one of `invoke`, `ok`, `info` or `fail` (error);
-- - `process` is present and is a number or a string (error);
-- - for a string (nemesis) `process`, `type` is `info` (error);
-- - for a numeric (client) `process`:
--   - an `invoke` does not follow an unfinished `invoke` (error);
--   - an `invoke` does not follow an `info` completion, i.e. no
--     invocation by a crashed process (error);
--   - a completion (`ok`, `fail`, `info`) follows an `invoke`
--     (error);
-- - if `index` is present, it is a numeric integer (error),
--   unique (error) and strictly ascending (error); a duplicate is
--   reported once;
-- - if `time` is present, it is numeric (error) and monotonic
--   (warning);
-- - no `invoke` is left without a completion at the end (error).
--
-- "Numeric" means a Lua number or a numeric cdata value (for
-- example, a Tarantool 64-bit monotonic clock). Warnings do not
-- make a history invalid: the function then returns `true`
-- together with a non-empty list of findings.
--
-- @param x History object or array of operations.
-- @return boolean, table|nil
--
-- @function is_well_formed
local function is_well_formed(x)
    local ops = x
    if type(x) == 'table' and getmetatable(x) == mt then
        ops = x.history
    end

    if type(ops) ~= 'table' then
        return false, { finding('error', ('history is not a table: %s')
            :format(tostring(ops)), nil) }
    end

    local findings = {}
    local state = {
        pending = {},
        crashed = {},
        seen_index = {},
        last_index = nil,
        last_time = nil,
    }

    ---@type number
    local max = 0
    local count = 0
    local has_non_numeric_key = false
    for key in pairs(ops) do
        if type(key) == 'number' then
            count = count + 1
            if key > max then
                max = key
            end
        else
            has_non_numeric_key = true
        end
    end
    if has_non_numeric_key then
        add_error(findings, 'history has a non-numeric key', nil)
    end
    if max == count then
        for i = 1, max do
            check_op(ops[i], findings, state, i)
        end
    else
        -- The history is sparse. Walk existing numeric keys in
        -- order instead of iterating up to the largest key.
        local keys = {}
        for key in pairs(ops) do
            if type(key) == 'number' then
                table.insert(keys, key)
            end
        end
        table.sort(keys)
        for _, key in ipairs(keys) do
            check_op(ops[key], findings, state, key)
        end
        add_error(findings, 'history is not a dense array', nil)
    end

    -- A history must not contain dangling invocations without a
    -- completion.
    for process, invoke_op in pairs(state.pending) do
        add_error(findings, ('process %s has a dangling invoke')
            :format(tostring(process)), invoke_op)
    end

    local ok = true
    for _, item in ipairs(findings) do
        if item.severity == 'error' then
            ok = false
            break
        end
    end

    if #findings == 0 then
        return true, nil
    end
    return ok, findings
end

-- Get a string representation of history.
-- @return string
-- @function to_txt
local function to_txt(self)
    dev_checks('<history>')

    local history_str = { '' }
    for _, operation in ipairs(self.history) do
        local op_str = ('%3d    %s'):format(
            operation.process, op.to_string(operation))
        table.insert(history_str, op_str)
    end

    return table.concat(history_str, '\n')
end

-- Get a string representation of history encoded to JSON.
-- @return string
-- @function to_json
local function to_json(self)
    dev_checks('<history>')

    return json.encode(self.history)
end

-- Get a table with completed operations in a history.
-- @return table
-- @function ops_completed
local function ops_completed(self)
    dev_checks('<history>')

    return gen.filter(op.is_completed, self.history):length()
end

-- Get a table with planned operations in a history.
-- @return table
-- @function ops_planned
local function ops_planned(self)
    dev_checks('<history>')

    return gen.filter(op.is_planned, self.history):length()
end

-- Add an operation to a history.
-- @return true
-- @function add
local function add(self, operation)
    dev_checks('<history>', '<operation>|table')
    table.insert(self.history, operation)

    return true
end

mt = {
    __type = '<history>',
    __index = {
        add = add,
        ops_planned = ops_planned,
        ops_completed = ops_completed,
        to_json = to_json,
        to_txt = to_txt,
        is_well_formed = is_well_formed,
    },
}

-- Create a new history object.
-- @return history
-- @function new
local function new()
    return setmetatable({
        history = {},
    }, mt)
end

return {
    new = new,
    is_well_formed = is_well_formed,
}
