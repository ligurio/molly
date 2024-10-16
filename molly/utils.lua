---- Helpers.
-- @module molly.utils

local ffi = require('ffi')

ffi.cdef[[
extern char **environ;

int setenv(const char *name, const char *value, int overwrite);
int unsetenv(const char *name);
int chdir(const char *dirname);
char* getcwd(char *buffer, int maxlen);
]]

--- Set and unset environment variable.
-- @string key Variable name.
-- @string value Variable value.
-- @raise error
-- @return true
--
-- @function setenv
local function setenv(key, value)
    local rc
    if value ~= nil then
        rc = ffi.C.setenv(key, tostring(value), 1)
    else
        rc = ffi.C.unsetenv(key)
    end
    if rc == -1 then
	error(('Error: %s'):format(ffi.errno().errstring()))
    end

    return true
end

--- Get current directory.
-- @return string, absolute path to a current directory
--
-- @function cwd
local function cwd()
    local length = 2048
    local dir = ffi.new("char[?]", length)
    ffi.C.getcwd(dir, length)
    return ffi.string(dir)
end

--- Change current directory.
-- @string dir
-- @return boolean
--
-- @function chdir
local function chdir(dir)
    return ffi.C.chdir(dir) == 0
end

--- Defines whether we run under Tarantool.
-- @return boolean
--
-- @function is_tarantool
local function is_tarantool()
    return _G['_TARANTOOL'] ~= nil
end

--- Function equivalent to basename in POSIX systems
-- @string path
-- @return string
--
-- @function basename
local function basename(str)
    local name = string.gsub(str, "(.*/)(.*)", "%2")
    return name
end

--- Packs the given arguments into a table with an `n` key
-- denoting the number of elements.
-- @return table
--
-- @function pack
local function pack(...)
    return {
        n = select("#", ...), ...
    }
end

local function is_callable(object)
    if type(object) == 'function' then
        return true
    end

    -- All objects with type `cdata` are allowed because there is
	-- no easy way to get metatable.__call of object with type
	-- `cdata`.
    if type(object) == 'cdata' then
        return true
    end

    local object_metatable = getmetatable(object)
    if (type(object) == 'table' or type(object) == 'userdata') then
        -- If metatable type is not `table` -> metatable is
		-- protected -> cannot detect metamethod `__call` exists.
        if object_metatable and
		   type(object_metatable) ~= 'table' then
            return true
        end

        -- The `__call` metamethod can be only the `function`
        -- and cannot be a `table`, `userdata` or `cdata`
        -- with `__call` methamethod on its own.
        if object_metatable and object_metatable.__call then
            return type(object_metatable.__call) == 'function'
        end
    end

    return false
end

return {
    basename = basename,
    is_callable = is_callable,
    chdir = chdir,
    cwd = cwd,
    setenv = setenv,
    pack = pack,

    is_tarantool = is_tarantool,
}
