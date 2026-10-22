---- Module with default Molly client.
-- @module molly.client
--
-- A client is executed by a thread pool in a number of stages:
-- open a connection, set up the DB, invoke operations, tear down
-- and close. When a runner passes `opts.barriers`
-- (see `molly.thread`), threads synchronize at stage
-- boundaries: no thread runs operations until every thread opened
-- a connection and set up the DB, and no thread tears down until
-- every thread finished operations. Only `open`, `setup` and
-- `invoke` boundaries are synchronized; threads tear down and
-- close connections independently after the last barrier.
--
-- An operation that crashed a client, or an `invoke` that
-- returned an invalid completion, is recorded as an `info`
-- operation (an indeterminate state) and the process is
-- restarted, as in Jepsen. A client that is not reusable is
-- reopened before the next operation; see the `reusable`
-- method below.
--
-- @see molly.gen
-- @see molly.tests
-- @see molly.thread

local clock = require('molly.clock')
local dev_checks = require('molly.dev_checks')
local log = require('molly.log')
local op_lib = require('molly.op')
local thread = require('molly.thread')
local utils = require('molly.utils')

local op_index = 1

-- Synchronize threads at a stage boundary. A runner passes a
-- table with barriers (`opts.barriers`) sized to a number of
-- client threads. When the client is executed directly without
-- barriers, the call is a no-op. A missing barrier for a stage is
-- an error: a partially populated table would silently skip
-- synchronization.
local function sync_stage(opts, stage)
    if opts.barriers == nil then
        return
    end
    local barrier = opts.barriers[stage]
    if barrier == nil then
        error(('no barrier for stage "%s"'):format(stage))
    end
    barrier:wait()
end

-- Reserve the next index in a history.
local function next_index()
    local index = op_index
    op_index = op_index + 1
    return index
end

-- A client is reusable when it survives a crashed invocation
-- without a restart. By default a client is not reusable, as in
-- Jepsen. A client may implement an optional
-- `reusable(client, client_data)` method that returns a boolean.
-- An error raised by the method propagates to the caller, which
-- records the operation as indeterminate, as in Jepsen.
local function is_reusable(client, client_data)
    if type(client.reusable) ~= 'function' then
        return false
    end
    return client.reusable(client, client_data) == true
end

-- Completion types accepted by Jepsen. An invocation is not a
-- valid completion.
local completion_types = {
    ok = true,
    info = true,
    fail = true,
}

-- Validate a completion against its invocation, as the Jepsen
-- client validator does. A completion must be a table with a
-- valid type and must preserve the process and the function of
-- the invocation.
local function validate_completion(op, res)
    if type(res) ~= 'table' then
        return false, 'completion is not a table'
    end
    if not completion_types[res.type] then
        return false, ('invalid completion type "%s"'):format(
            tostring(res.type))
    end
    if res.process ~= op.process then
        return false, 'completion process does not match the invocation'
    end
    if res.f ~= op.f then
        return false, 'completion f does not match the invocation'
    end
    return true
end

-- Advance a process identifier after an indeterminate operation,
-- so that subsequent operations are recorded under a new process,
-- as in Jepsen. Process identifiers are unique within a run.
local function next_process(state)
    local context = state.context
    if context ~= nil and context.next_process ~= nil then
        state.process = context.next_process
        context.next_process = context.next_process + 1
    else
        state.process = state.process + 1
    end
end

-- Record an indeterminate completion for an invocation that
-- cannot be completed normally: the operation may or may not
-- have taken place. The process is restarted with a new
-- identifier and the client is marked for a reopen, as in
-- Jepsen. Every invocation is paired with a completion, so a
-- history never has a dangling invoke.
local function add_indeterminate(history, op, state, thread_id_str, reason)
    state.needs_reopen = true
    local failed_op = utils.copy_table(op)
    failed_op.type = 'info'
    failed_op.process = state.process
    failed_op.index = next_index()
    failed_op.time = clock.monotonic64()
    failed_op.error = 'indeterminate: ' .. tostring(reason)
    log.debug('%-4s %s', thread_id_str, op_lib.to_string(failed_op))
    history:add(failed_op)
    next_process(state)
end

local function process_operation(client, history, op, thread_id_str, state,
        client_data)
    dev_checks('<client>', '<history>', '!', 'string', 'table', 'table')

    if utils.is_callable(op) then
        op = op()
    end

    assert(type(op) == 'table', 'Type of operation is not a Lua table.')

    -- A generator may yield the same operation table more than
    -- once (for example `gen.duplicate`). Copy it before
    -- annotating so that history entries do not alias the
    -- generator's table.
    op = utils.copy_table(op)

    op.type = 'invoke'
    op.process = state.process
    op.index = next_index()
    op.time = clock.monotonic64()
    if log.is_enabled('debug') then
        log.debug('%-4s %s', thread_id_str, op_lib.to_string(op))
    end
    history:add(op)

    -- A crashed client may be in an unknown state. When it is not
    -- reusable, reopen the connection before the next operation.
    -- A failed reconnect is recorded as a 'fail' operation and
    -- retried on the next operation, as in Jepsen. An error
    -- raised by reusable() or close() is a crash of the current
    -- invocation: the operation is indeterminate, so it is
    -- recorded as 'info' and the process is restarted.
    if state.needs_reopen then
        local reuse_ok, reusable = pcall(is_reusable, client, client_data)
        if not reuse_ok then
            log.warn('Process %d crashed (reusable failed: %s)',
                state.process, reusable)
            add_indeterminate(history, op, state, thread_id_str, reusable)
            return
        end
        if reusable then
            state.needs_reopen = false
        else
            local close_ok, close_err = pcall(client.close, client,
                client_data)
            if not close_ok then
                log.warn('Process %d crashed (close failed: %s)',
                    state.process, close_err)
                add_indeterminate(history, op, state, thread_id_str,
                    close_err)
                return
            end
            local ok, err = pcall(client.open, client, state.addr, client_data)
            if not ok then
                log.info('ERROR: %s', err)
                local failed_op = {
                    type = 'fail',
                    f = op.f,
                    value = op.value,
                    process = state.process,
                    index = next_index(),
                    time = clock.monotonic64(),
                    error = 'no-client: ' .. tostring(err),
                }
                log.debug('%-4s %s', thread_id_str,
                    op_lib.to_string(failed_op))
                history:add(failed_op)
                return
            end
            state.needs_reopen = false
        end
    end

    local ok, res = pcall(client.invoke, client, op, client_data)
    if not ok then
        log.warn('Process %d crashed (%s)', state.process, res)
        -- A crashed operation is indeterminate: it may or may
        -- not have taken place. Record it as 'info' and restart
        -- the process, as in Jepsen.
        add_indeterminate(history, op, state, thread_id_str, res)
        return
    end
    -- A client must return a valid completion operation. An
    -- invalid result is indeterminate as well: the invocation is
    -- already in the history and cannot be left without a
    -- completion. Record it as 'info' and restart the process,
    -- as in Jepsen. Jepsen's validator requires a map with a
    -- type of ok, info or fail and the process and f of the
    -- invocation.
    local valid, reason = validate_completion(op, res)
    if not valid then
        log.warn('Process %d crashed (%s)', state.process, reason)
        add_indeterminate(history, op, state, thread_id_str, reason)
        return
    end
    -- A client may return the same table it was given. Copy the
    -- completion before annotating it, so it does not overwrite
    -- the already recorded invoke. The index and time of a
    -- completion are always assigned by Molly, as in Jepsen.
    res = utils.copy_table(res)
    res.index = next_index()
    res.time = clock.monotonic64()
    if log.is_enabled('debug') then
        log.debug('%-4s %s', thread_id_str, op_lib.to_string(res))
    end
    history:add(res)

    -- A client that returned an indeterminate operation has to be
    -- restarted as well.
    if res.type == 'info' then
        state.needs_reopen = true
        next_process(state)
    end
end

---@async
local function run_client(thread_id, opts)
    dev_checks('number', 'table')

    local client = opts.client
    local ops_generator = opts.gen
    local history = opts.history

    -- TODO: Use fun.cycle() and closure.
    local nth = math.random(1, #opts.nodes)
    local addr = opts.nodes[nth]

    -- A shared context holds the next process identifier. After
    -- an indeterminate operation a thread gets a fresh process,
    -- as in Jepsen; identifiers are unique within a run.
    local context = opts.context
    if context == nil then
        context = { next_process = (opts.threads or 1) + 1 }
        opts.context = context
    end

    local client_data = {}
    local thread_state = {
        process = thread_id,
        needs_reopen = false,
        context = context,
        addr = addr,
    }
    log.debug('Opening connection by thread %d to DB (%s)', thread_id, addr)
    local ok, err = pcall(client.open, client, addr, client_data)
    if not ok then
        log.error('Failed to open connection: %s', err)
        error(err, 0)
    end

    -- Wait until every thread opened a connection before setting
    -- up the DB.
    sync_stage(opts, 'open')

    log.debug('Setting up DB (%s) by thread %d', addr, thread_id)
    ok, err = pcall(client.setup, client, client_data)
    if not ok then
        log.error('Failed to set up DB: %s', err)
        error(err, 0)
    end

    -- Wait until every thread set up the DB before running
    -- operations.
    sync_stage(opts, 'setup')

    -- A generator cursor is shared by all client threads and
    -- lives in the shared worker options, so that every operation
    -- generated by a workload is invoked exactly once. The first
    -- thread to reach this point initializes the cursor.
    local gen, param, state = ops_generator:unwrap()
    if opts.gen_state == nil then
        opts.gen_state = state
    end
    local op
    local thread_id_str = '[' .. tostring(thread_id) .. ']'
    while true do
        state, op = gen(param, opts.gen_state)
        if state == nil then
            break
        end
        opts.gen_state = state
        ok, err = pcall(process_operation, client, history, op, thread_id_str,
            thread_state, client_data)
        if ok == false then
            error(('Failed to process an operation: %s'):format(
                tostring(err)), 0)
        end

        thread.yield()
    end

    -- Wait until every thread finished operations before tearing
    -- down.
    sync_stage(opts, 'invoke')

    log.debug('Tearing down DB (%s) by thread %d', addr, thread_id)
    ok, err = pcall(client.teardown, client, client_data)
    if not ok then
        log.error('Failed to tear down DB: %s', err)
        error(err, 0)
    end

    log.debug('Closing connection to DB (%s) by thread %d', addr, thread_id)
    ok, err = pcall(client.close, client, client_data)
    if not ok then
        log.error('Failed to close connection: %s', err)
        error(err, 0)
    end

    return true, nil
end

-- https://www.lua.org/pil/16.2.html

local client_mt = {
    __type = '<client>',
    __index = {
        open = function() return true end,
        setup = function() return true end,
        invoke = function(_self, op)
            return { type = 'ok', f = op.f, process = op.process }
        end,
        teardown = function() return true end,
        close = function() return true end,
        -- A client is not reusable by default, as in Jepsen.
        reusable = function() return false end,
    }
}

--- Function that returns a default client implementation.
--
-- Default implementation of a client defines open, setup,
-- teardown and close methods with empty implementation that
-- always returns true. Its invoke method completes every
-- operation with `ok`, like a no-op client in Jepsen.
--
-- Client must implement the following methods:
--
-- **open** - function that open a connection to a database
-- instance. Function must raise an error on failure. Two
-- arguments are passed to the function:
--   - `address` - an 'address' of the remote node
--   - `client_data` - a table with client's data
--
-- **setup** - function that set up a database instance. Function
-- must raise an error on failure. A single argument is passed
-- to the function:
--   - `client_data` - a table with client's data
--
-- **invoke** - function that accept an operation and invoke it
-- on database instance, function should process user-defined
-- types of operations and execute intended actions on databases.
-- Function must return an operation after invocation.
-- Two arguments are passed to the function:
--   - `op` - an operation generated by a test generator
--   - `client_data` - a table with client's data
--
-- An `invoke` that raises an error crashes the client. The
-- operation is recorded in a history as `info` (an indeterminate
-- state: it may or may not have taken place) and the process is
-- restarted. See `reusable` below. An `invoke` that returns an
-- invalid completion is treated the same way: the invocation is
-- recorded as `info` and the process is restarted, so a history
-- never has a dangling `invoke`. A completion is invalid when it
-- is not a table, its type is not `ok`, `info` or `fail`, or its
-- `process` or `f` differs from the invocation, as in Jepsen.
--
-- **teardown** - function that tear down a database instance.
-- Function must raise an error on failure. Single argument is
-- passed to the function:
--   - `client_data` - a table with client's data
--
-- **close** - function that close connection to a database
-- instance. Function must raise an error on failure. Single
-- argument is passed to the function:
--   - `client_data` - a table with client's data
--
-- **reusable** - optional function that reports whether a client
-- survives a crashed invocation without a restart. A single
-- argument is passed to the function:
--   - `client_data` - a table with client's data
-- A client is not reusable by default, as in Jepsen: after a
-- crashed `invoke` (or an `invoke` that returned `info`) the
-- connection is reopened with `close` and `open` before the next
-- operation. An error raised by `reusable` or `close` during a
-- reopen marks the next invocation as `info` and restarts the
-- process, as in Jepsen. A failed `open` is recorded as a `fail`
-- operation and retried on the next operation.
--
-- In general it is recommended to raise an error in case of fatal
-- errors like failed database setup, teardown or connection and
-- set status of operation to 'fail' when key is not found in
-- database table etc. A returned `false` is not treated as a
-- failure and does not abort a run.
--
-- @return client
-- @usage
-- local client = require('molly').client.new()
-- client.invoke = function(op)
--     return true
-- end
--
-- @see molly.tests
-- @see molly.gen
-- @see molly.op
--
-- @function new
local function new()
    return setmetatable({
        storage = {},
    }, client_mt)
end

return {
    new = new,

    run = run_client,
}
