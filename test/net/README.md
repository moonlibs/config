# Split-Brain test toolchain

## Run

```bash
$ pwd
config/test

$ docker compose up --build
```

## Prepare

### Prepare instance_01

```bash
docker exec -it instance_001 /bin/sh

# make setup must be executed only once per container
/opt/tarantool $ make -C net setup
```

### Prepare instance_02

```bash
docker exec -it instance_002 /bin/sh

# make setup must be executed only once per container
/opt/tarantool $ make -C net setup
```

## Make online

```bash
docker exec -it instance_01 /bin/sh

/opt/tarantool $ make -C net online
```

## Isolation

### Isolate instance_01 against instance_02

```bash
docker exec -it instance_01 /bin/sh

/opt/tarantool $ make -C net offline-dst-instance_02
```

### Isolate instance_01 against etcd

```bash
docker exec -it instance_01 /bin/sh

/opt/tarantool $ make -C net offline-dst-etcd
```

### Total instance_01 isolation

```bash
docker exec -it instance_01 /bin/sh

/opt/tarantool $ make -C net offline-dst-instance_02
/opt/tarantool $ make -C net offline-dst-etcd
```

### Split brain instance_01 / instance_02

```bash
docker exec -it instance_01 /bin/sh

/opt/tarantool $ make -C net offline-dst-instance_02
/opt/tarantool $ make -C net offline-dst-autofailover-2
```

```bash
docker exec -it instance_02 /bin/sh

/opt/tarantool $ make -C net offline-dst-instance_01
/opt/tarantool $ make -C net offline-dst-autofailover-1
```
