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

return {
    basename = basename,
    chdir = chdir,
    cwd = cwd,
    setenv = setenv,
    pack = pack,

    is_tarantool = is_tarantool,
}
