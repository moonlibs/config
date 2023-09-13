FROM tarantool/tarantool:2.11.1
RUN apk add --no-cache -u iproute2 make bind-tools

WORKDIR /opt/tarantool
RUN tarantoolctl rocks --global --server http://moonlibs.github.io/rocks install package-reload scm-1

CMD ["tarantool" "/opt/tarantool/init.lua"]
