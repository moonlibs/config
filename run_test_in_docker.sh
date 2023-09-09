#!/bin/sh

pwd
rm -rf /root/.cache/
cp -ar /root/.rocks /source/config/.rocks
/source/config/.rocks/bin/luatest --coverage -v spec/
