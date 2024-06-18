-- Returns a new table, recursively copied from the one given.
--
-- @param   table   table to be copied
-- @return  table
local function tbl_copy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == "table" then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[tbl_copy(orig_key)] = tbl_copy(orig_value)
        end
    -- number, string, boolean, etc.
    else
        copy = orig
    end
    return copy
end

return {
    copy = tbl_copy,
}
