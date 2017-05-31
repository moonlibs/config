package = 'config'
version = 'scm-1'
source  = {
    url    = 'git://github.com/moonlibs/tnt-config.git',
    branch = 'master',
}
description = {
    summary  = "Package for loading external lua config",
    homepage = 'https://github.com/moonlibs/tnt-config.git',
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
