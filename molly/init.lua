---- Framework for distributed system's verification, with fault injection.
-- @module molly
-- @author Sergey Bronnikov
-- @license ISC
-- @copyright Sergey Bronnikov, 2021-2022

local client = require('molly.client')
local db = require('molly.db')
local gen = require('molly.gen')
local log = require('molly.log')
local nemesis = require('molly.nemesis')
local runner = require('molly.runner')
local tests = require('molly.tests')
local utils = require('molly.utils')

return {
    client = client,
    db = db,
    gen = gen,
    log = log,
    nemesis = nemesis,
    runner = runner,
    tests = tests,
    utils = utils,
}
