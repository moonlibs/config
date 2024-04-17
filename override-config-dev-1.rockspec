package = "override-config"
version = "dev-1"
source = {
   url = "git+https://github.com/moonlibs/config",
   branch = "master"
}
description = {
   summary = "Package for loading external lua config (override)",
   homepage = "https://github.com/moonlibs/config.git",
   license = "BSD"
}
dependencies = {
   "lua >= 5.1"
}
build = {
   type = "builtin",
   modules = {
      ["override.config"] = "config.lua",
      ["override.config.etcd"] = "config/etcd.lua"
   }
}
