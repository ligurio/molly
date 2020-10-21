---- Module with functions for logging.
-- @module molly.log

-- log.lua
--
-- Copyright (c) 2016 rxi
--
-- This library is free software; you can redistribute it and/or modify it
-- under the terms of the MIT license. See LICENSE for details.
--
-- Source: https://github.com/rxi/log.lua

local clock = require('molly.clock')
local utils = require('molly.utils')

local log = { _version = "0.1.0" }

log.outfile = nil
log.level = "info"

local modes = {
    { name = "trace" },
    { name = "debug" },
    { name = "info" },
    { name = "warn" },
    { name = "error" },
    { name = "fatal" },
}

local levels = {}
for i, v in ipairs(modes) do
    levels[v.name] = i
end

--- Log message with verbose level 'trace'.
-- @string message Message.
-- @return nil
--
-- @function trace

--- Log message with verbose level 'debug'.
-- @string message Message.
-- @usage
-- > local log = require('molly.log')
-- > log.debug('Total planned requests: 1010')
-- [DEBUG 2021-12-1 12:26:8:689379] /home/sergeyb/sources/molly/jepsen/runner.lua:80: Total planned requests: 1010
--
-- @return nil
--
-- @function debug

--- Log message with verbose level 'info'.
-- @string message Message.
-- @return nil
-- @usage
-- > local log = require('molly.log')
-- > log.info('Message')
-- [INFO  2021-12-7 13:17:46:073544]: Message
--
-- @function info

--- Log message with verbose level 'warn'.
-- @string message Message.
-- @return nil
-- @usage
-- > local log = require('jepsen.log')
-- > log.warn('Message')
-- [WARN  2021-12-7 13:17:46:073544]: Message
--
-- @function warn

--- Log message with verbose level 'error'.
-- @string message Message.
-- @return nil
--
-- @function error

--- Log message with verbose level 'fatal'.
-- @string message Message.
-- @return nil
--
-- @function fatal

for i, x in ipairs(modes) do
    local nameupper = x.name:upper()
    log[x.name] = function(...)
        -- Return early if we're below the log level.
        if i < levels[log.level] then
          return
        end

        local msg = string.format(...)
        local lineinfo = ''
        if log.level == 'debug' then
            local debug_info = debug.getinfo(2, "Sl")
            local filename = utils.basename(debug_info.short_src)
            lineinfo = (' %s:%d'):format(filename, debug_info.currentline)
        end

        local timestamp = clock.dt()
        local str = ('[%-6s%-24s]%s: %s\n'):format(nameupper, timestamp, lineinfo, msg)
        -- Output to console.
        io.write(str)

        -- Output to log file.
        if log.outfile then
            local fp = io.open(log.outfile, "a")
            fp:write(str)
            fp:close()
        end
    end
end

return log
