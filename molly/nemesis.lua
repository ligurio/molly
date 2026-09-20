---- Module with nemeses.
-- @module molly.nemesis
--
-- A nemesis is a process that will be fed operations from a
-- generator process and then take action against the system
-- accordingly.
--
--    { type = "info", f = "start", process =
--        { "nemesis", time = 5326396898, index = 169 }}
--    { type = "info", f = "start", process =
--        { "nemesis", time = 5328551016, index = 170 }}

--- Nemesis that do nothing.
-- @return None
-- @function noop
local function noop()

    -- Do nothing.

    return {
        type = 'info',
        -- Possible values are 'start' and 'stop'.
        f = 'start',
        -- Always is 'nemesis'.
        process = 'nemesis',
        -- Time of start or end of nemesis.
        time = 5326396898,
        -- Nemesis's index.
        index = 169,
        -- Payload.
        value = nil,
    }
end

return {
    noop = noop,
}
