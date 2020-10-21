---- Module with nemeses.
-- @module molly.nemesis
--
-- A nemesis is a process that will be fed operations from a generator process
-- and then take action against the system accordingly.
--
--    { type = "info", f = "start", process = { "nemesis", time = 5326396898, index = 169 }}
--    { type = "info", f = "start", process = { "nemesis", time = 5328551016, index = 170 }}

--- Nemesis that do nothing.
-- @return None
-- @function noop
local function noop()

    -- Do nothing.

    return {
        type = 'info',
        f = 'start',            -- possible values are 'start' and 'stop'
        process = 'nemesis',    -- always is 'nemesis'
        time = 5326396898,      -- time of start or end of nemesis
        index = 169,            -- nemesis's index
        value = nil,            -- payload
    }
end

return {
    noop = noop,
}
