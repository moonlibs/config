FROM tarantool/tarantool:1.10.14
RUN apk add --no-cache -u iproute2 make bind-tools

WORKDIR /opt/tarantool

CMD ["tarantool" "/opt/tarantool/init.lua"]
