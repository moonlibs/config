package = 'config'
version = 'scm-6'
source  = {
    url    = 'git+https://github.com/moonlibs/config.git',
    branch = 'master',
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
        ['override.config'] = 'config.lua';
        ['override.config.etcd'] = 'config/etcd.lua';
    }
}

-- vim: syntax=lua
