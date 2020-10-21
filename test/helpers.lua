-- local setenv = require('molly.utils').setenv

-- if os.getenv('DEV') == nil then
--     setenv('DEV', 'ON')
-- end

local function file_exists(name)
    if name == nil then
        return false
    end

    local f = io.open(name, 'r')
    if f ~= nil then
        io.close(f)
        return true
    else
        return false
    end
end

return {
    file_exists = file_exists,
}
