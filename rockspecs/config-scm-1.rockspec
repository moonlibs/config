package = 'config'
version = 'scm-1'
source  = {
    url    = 'git+https://github.com/moonlibs/config.git',
    branch = 'v1',
}
description = {
    summary  = "Package for loading external lua config",
    homepage = 'https://github.com/moonlibs/config.git',
    license  = 'BSD',
}
dependencies = {
    'lua >= 5.1'
}
build = {
    type = 'builtin',
    modules = {
        ['config'] = 'config.lua'
    }
}

-- vim: syntax=lua
