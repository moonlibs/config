#!/bin/sh

pwd
rm -rf /root/.cache/
.rocks/bin/luatest -c -v spec/01_single_test.lua