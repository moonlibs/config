FROM tarantool/tarantool:2.10
RUN apk add --no-cache -u iproute2 make bind-tools

WORKDIR /opt/tarantool

CMD ["tarantool" "/opt/tarantool/init.lua"]