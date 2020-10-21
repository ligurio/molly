package = 'molly'
version = 'scm-1'
source = {
    url = 'git+https://github.com/ligurio/molly',
    branch = 'master',
}

description = {
    summary = 'A framework for distributed systems verification, with fault injection',
    homepage = 'https://github.com/ligurio/molly',
    maintainer = 'Sergey Bronnikov <estetus@gmail.com>',
    license = 'ISC',
}

dependencies = {
    'lua >= 5.1',
}

build = {
    type = 'make',
    -- Nothing to build.
    build_pass = false,
    variables = {
        LUADIR='$(LUADIR)',
    },
    copy_directories = {
    },
}
