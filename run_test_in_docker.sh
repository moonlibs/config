#!/bin/sh

pwd
rm -rf /root/.cache/
cp -ar /root/.rocks /source/config/
/source/config/.rocks/bin/luatest --coverage -vv spec/
