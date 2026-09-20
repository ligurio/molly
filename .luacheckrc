globals = {
    "box",
    "checkers",
    "package",
}

max_code_line_length = 80
max_comment_line_length = 66

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

-- Long external URLs and verbatim examples in comments cannot be
-- wrapped to fit into the default max_comment_line_length, so
-- relax the limit for files that contain them.
files["molly/gen.lua"] = {
    max_comment_line_length = 105,
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
