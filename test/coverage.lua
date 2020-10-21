local utils = require('molly.utils')
local runner = require('luacov.runner')

-- Module with utilities for collecting code coverage from external processes.
local export = {
    DEFAULT_EXCLUDE = {
        '^builtin/',
        '/luarocks/',
        '/build.luarocks/',
        '/.rocks/',
    },
}

local function with_cwd(dir, fn)
    local old = utils.cwd()
    assert(utils.chdir(dir), 'Failed to chdir to ' .. dir)
    fn()
    assert(utils.chdir(old), 'Failed to chdir to ' .. old)
end

local function coverage_enable()
    local root = utils.cwd()
    -- Change directory to the original root so luacov can find default config
    -- and resolve relative filenames.
    with_cwd(root, function()
        local config = runner.load_config()
        config.exclude = config.exclude or {}
        for _, item in pairs(export.DEFAULT_EXCLUDE) do
            table.insert(config.exclude, item)
        end
        runner.init(config)
    end)
end

function export.enable()
        coverage_enable()
end

function export.shutdown()
    if runner.initialized then
        runner.shutdown()
    end
end

return export
