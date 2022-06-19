-- https://www.sqlite.org/isolation.html
-- https://www.sqlite.org/threadsafe.html
-- https://www.sqlite.org/atomiccommit.html

local sqlite3 = require('lsqlite3')
local molly = require('molly')
local os = require('os')

print('SQLite version:', sqlite3.version())
print('lsqlite3 library version:', sqlite3.lversion())

local function call_insert(stmt, key, val) -- luacheck: no unused
    assert(stmt:isopen() == true, 'statement has been finalized')
    local ok = stmt:bind_values(key, val)
    if ok ~= sqlite3.OK then
        return false
    end
    ok = stmt:step()
    if ok ~= sqlite3.DONE then
        return false
    end
    stmt:reset()

    return true
end

local function call_select(stmt, key) -- luacheck: no unused
    assert(stmt:isopen() == true, 'statement has been finalized')
    local val, ok
    if stmt:bind_values(key) ~= sqlite3.OK then
        return false
    end
    if stmt:step() == sqlite3.ROW then
        val = stmt:get_value(0)
        ok = true
    else
        ok = false
    end
    stmt:reset()

    return ok, val
end

-- `sqlite_rw_register` is a client that performs on database two operations:
-- `read` and `write`. Method `invoke` must apply these operations to a
-- database instance.
local sqlite_rw_register = molly.client.new()

sqlite_rw_register.open = function(self)
    self.db = assert(sqlite3.open_memory(), 'database handle is nil')
    -- For explanation see https://www.sqlite.org/pragma.html
    assert(sqlite3.OK == self.db:exec('PRAGMA journal_mode = WAL'))
    assert(sqlite3.OK == self.db:exec('PRAGMA synchronous = normal'))
    assert(sqlite3.OK == self.db:exec('PRAGMA mmap_size = 30000000000'))
    assert(sqlite3.OK == self.db:exec('PRAGMA page_size = 32768'))

    --self.insert_stmt = assert(self.db:prepare('INSERT INTO rw_register VALUES (?, ?)'), 'statement prepare')
    --self.select_stmt = assert(self.db:prepare('SELECT val FROM rw_register WHERE id = ?'), 'statement prepare')
    return true
end

sqlite_rw_register.setup = function(self)
    assert(sqlite3.OK == self.db:exec('CREATE TABLE IF NOT EXISTS rw_register (id, val)'))
    return true
end

local OP_TYPE = 1
local OP_VAL = 3

local KEY_ID = 1

sqlite_rw_register.invoke = function(self, op)
    local val = op.value[1]
    local type = 'ok'
    if val[OP_TYPE] == 'r' then
        --[[
        assert(self.select_stmt:isopen() == true, 'statement has been finalized')
        local ok, v = call_select(self.select_stmt, KEY_ID)
        val[OP_VAL] = v
        if ok == false then
            type = 'fail'
        end
        ]]
        val[OP_VAL] = self.db:exec(string.format('SELECT val FROM rw_register WHERE id = %d', KEY_ID))
    elseif val[OP_TYPE] == 'w' then
        --assert(self.insert_stmt:isopen() == true, 'statement has been finalized')
        --local ok = call_insert(self.insert_stmt, KEY_ID, val[OP_VAL])
        local ok = self.db:exec(string.format('INSERT INTO rw_register VALUES (?, ?)', KEY_ID, val[OP_VAL]))
        if ok == false then
            type = 'fail'
        end
    else
        error('Unknown operation')
    end

    return {
        value = { val },
        f = op.f,
        process = op.process,
        type = type,
    }
end

sqlite_rw_register.teardown = function(self)
    --self.insert_stmt:finalize()
    --self.select_stmt:finalize()
    local changes = self.db:total_changes()
    assert(changes == 500, string.format('Number of operations is wrong (%d != 500)', changes))
    print('Total changes in SQLite DB:', changes)
    return true
end

sqlite_rw_register.close = function(self)
    self.db:close()
    return true
end

local test_options = {
    create_reports = true,
    threads = 5,
    nodes = {
        '1',
    },
}

local ok, err = molly.runner.run_test({
    client = sqlite_rw_register,
    generator = molly.tests.rw_register_gen():take(100),
}, test_options)

if not ok then
    print('Test has failed:', err)
end

if os.getenv('DEV') ~= 'ON' then
    os.remove('history.json')
    os.remove('history.txt')
end
