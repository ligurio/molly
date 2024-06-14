local pgsql =  require ("luasql.postgres")
local os = require('os')
local molly = require('molly')
local log = require('molly.log')

-- `pg_rw_register` is a client that performs on database two operations:
-- `read` and `write`. Method `invoke` must apply these operations to a
-- database instance.
local pg_rw_register = molly.client.new()


local threads = 5

local OP_TYPE = 1
local OP_VAL = 3
local KEY_ID = 1

local check = 500
local iterations = check * 2 


----- open database
pg_rw_register.open = function(self)

    local env = assert (pgsql.postgres())
    local con = assert (env:connect('test2', 'postgres', nil, "127.0.0.1", 5432))
    
    local res ={
        con = con,
        env = env,
    }
   return res 
end


pg_rw_register.setup = function(self, con)
    assert(con:execute("CREATE TABLE IF NOT EXISTS rw_register (id int, val int, ver int default 1)"))
    assert(con:execute("TRUNCATE TABLE rw_register"))

    return true
end

pg_rw_register.invoke = function(self, op, con)
    local val = op.value[1]
    local type = 'ok'

    if val[OP_TYPE] == 'r' then

        local res = con:execute(string.format('SELECT val FROM rw_register WHERE id = %d', KEY_ID))
        local row = res:fetch ({}, "a")
        
        if row == nil then
            val[OP_VAL] = nil
        else
            val[OP_VAL] = row.val
        end

    elseif val[OP_TYPE] == 'w' then

        -- print(string.format('w KEY_ID=%d val[%d]=%d', KEY_ID, OP_VAL, val[OP_VAL]))
        local sql = string.format('INSERT INTO rw_register(id,val) VALUES (%d, %d)', KEY_ID, val[OP_VAL])
        local ok = assert( con:execute(sql))
        if ok == false then
            print('insert fail')
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

pg_rw_register.teardown = function(self, con)
 
    -- local changes = self.db:total_changes()
        
    local res = assert(con:execute('SELECT sum(ver) as sum FROM rw_register'))
    local row = res:fetch ({}, "a")
    -- assert(changes == 500, string.format('Number of operations is wrong (%d != 500)', changes))
    
    if tonumber(row.sum) == check then
        log.debug('Total changes in Postgres DB is Ok [excepted %s]', row.sum )
    else
        log.debug('Total changes in Postgres DB is fail [excepted %s  call %d]', row.sum, check )
    end

    return true
end

-- finalize class
pg_rw_register.close = function(self, con)
    -- self.env:close()
    con:close()
    return true
end


local test_options = {
    create_reports = true,
    threads = threads,
    nodes = {
        'node 1',
        'node 2',
        'node 3',
        'node 4',
        'node 5',
        -- 'node 6',
    },
}


local ok, err = molly.runner.run_test({
    client = pg_rw_register,
    generator = molly.tests.rw_register_gen():take(iterations),
}, test_options)

if not ok then
    print('Test has failed:', err)
end

if os.getenv('DEV') ~= 'ON' then
    os.remove('history.json')
    os.remove('history.txt')
end
