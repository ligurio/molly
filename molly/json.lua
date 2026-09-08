local utils = require('molly.utils')

---@type table<string, any>
local json
if utils.is_tarantool() then
    json = require('json')
else
    json = require('cjson')
    -- LuaJIT's cjson provides a null sentinel as `cjson.null`,
    -- while Tarantool's json uses `json.NULL`. Expose the
    -- sentinel as `json.NULL` on both runtimes.
    json.NULL = json.null
end

return json
