project = 'molly'
title = 'Molly documentation'
description = 'A framework for distributed systems verification, with fault injection'
no_lua_ref = false
no_summary = false
ignore = true
all = true
not_luadoc = true
format = 'discount'
readme = 'README.md'

examples = {
    'test/examples/sqlite-rw-register.lua',
    'test/examples/sqlite-list-append.lua',
}

tparam_alias('table', 'table')
tparam_alias('integer', 'integer')
tparam_alias('boolean', 'boolean')

-- vim: ft=lua:
