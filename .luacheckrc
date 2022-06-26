globals = {
    "box",
    "checkers",
    "package",
}

ignore = {
    -- Accessing an undefined field of a global variable <debug>.
    "143/debug",
    -- Accessing an undefined field of a global variable <os>.
    "143/os",
    -- Accessing an undefined field of a global variable <string>.
    "143/string",
    -- Accessing an undefined field of a global variable <table>.
    "143/table",
    -- Unused argument <self>.
    "212/self",
    -- Shadowing an upvalue.
    "431",
}

files["molly/tests.lua"] = {
    ignore = {
        -- Line is too long.
        "631"
    }
}

include_files = {
    '.luacheckrc',
    '*.rockspec',
    '**/*.lua',
}

exclude_files = {
    '.rocks',
    'test/tap.lua',
    '3rd-party-tests',
}
