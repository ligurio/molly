local utils = require('molly.utils')

---@type table<string, any>
local json
if utils.is_tarantool() then
    json = require('json')
else
    json = require('cjson')
end

return json
