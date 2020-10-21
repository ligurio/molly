---- Module with default DB implementation.
-- @module molly.db
--
-- Allows Molly to set up and tear down databases.

local db_mt = {
    __type = '<db>',
    __index = {
        setup = function() return true end,
        teardown = function() return true end,
    }
}

--- Function that returns a default db implementation.
-- Molly db must implement following methods:
--
-- - **setup** - function that set up a database instance
-- - **teardown** - function that tear down a database instance
--
-- Default implementation of a DB defines setup and teardown methods with empty
-- implementation that always returns true.
-- @return db
--
-- @function new
local function new()
    return setmetatable({}, db_mt)
end

return {
    new = new,
}
