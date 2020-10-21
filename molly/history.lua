---- Module with functions that processes history of operations.
-- @module molly.history

local dev_checks = require('molly.dev_checks')
local gen = require('molly.gen')
local json = require('molly.json')
local op = require('molly.op')

-- Get a string representation of history.
-- @return string
-- @function to_txt
local function to_txt(self)
    dev_checks('<history>')

    local history_str = ''
    for _, operation in ipairs(self.history) do
        local op_str = ('%3d    %s'):format(operation.process, op.to_string(operation))
        history_str = ('%s\n%s'):format(history_str, op_str)
    end

    return history_str
end

-- Get a string representation of history encoded to JSON.
-- @return string
-- @function to_json
local function to_json(self)
    dev_checks('<history>')

    return json.encode(self.history)
end

-- Get a table with completed operations in a history.
-- @return table
-- @function ops_completed
local function ops_completed(self)
    dev_checks('<history>')

    return gen.filter(op.is_completed, self.history):length()
end

-- Get a table with planned operations in a history.
-- @return table
-- @function ops_planned
local function ops_planned(self)
    dev_checks('<history>')

    return gen.filter(op.is_planned, self.history):length()
end

-- Add an operation to a history.
-- @return true
-- @function add
local function add(self, operation)
    dev_checks('<history>', '<operation>|table')
    table.insert(self.history, operation)

    return true
end

-- Get a HdrHistogram (High Dynamic Range (HDR) Histogram)
--
-- Since Molly uses HdrHistogram and produces HdrHistogram logs, various tools
-- that plot and view histogram logs can be used to analyze Molly's data. Some
-- common tools include HistggramLogAnalyzer, HdrHistogramVisualizer, hdr-plot,
-- and a Javascript-based in-browser histogram log parser.
--
-- 1. https://github.com/HdrHistogram/HdrHistogram
-- 2. https://github.com/HdrHistogram/HistogramLogAnalyzer
-- 3. https://github.com/ennerf/HdrHistogramVisualizer
-- 4. https://hdrhistogram.github.io/HdrHistogramJSDemo/logparser.html
-- 5. https://github.com/BrunoBonacci/hdr-plot
--
-- Format: https://github.com/HdrHistogram/HdrHistogram/blob/master/GoogleChartsExample/example1.txt
--
-- @return table
-- @function hdr_histogram
local function hdr_histogram(self)
    return {}
end

local mt = {
    __type = '<history>',
    __index = {
        add = add,
        ops_planned = ops_planned,
        ops_completed = ops_completed,
        to_json = to_json,
        to_txt = to_txt,
        hdr_histogram = hdr_histogram,
    },
}

-- Create a new history object.
-- @return history
-- @function new
local function new()
    return setmetatable({
        history = {},
    }, mt)
end

return {
    new = new,
}
