# Config

Module to make proper initialization and configuration of tarantool instance.

It can be used with or without ETCD.

Only ETCD APIv2 now supported.

- [Config](#config)
  - [Status](#status)
  - [Installation](#installation)
  - [Configuration](#configuration)
    - [Example of `conf.lua`](#example-of-conflua)
    - [Usage in `init.lua`](#usage-in-initlua)
  - [Usage](#usage)
  - [Topologies](#topologies)
    - [Single-shard topology](#single-shard-topology)
      - [Example of `init.lua`](#example-of-initlua)
      - [Example of `/etc/userdb/conf.lua`](#example-of-etcuserdbconflua)
      - [Example of ETCD configuration (`etcd.cluster.master`)](#example-of-etcd-configuration-etcdclustermaster)
        - [Configuration precedence](#configuration-precedence)
      - [Fencing configuration](#fencing-configuration)
      - [Fencing algorithm](#fencing-algorithm)
    - [Operations during disaster](#operations-during-disaster)
    - [Multi-proxy topology (etcd.instance.single)](#multi-proxy-topology-etcdinstancesingle)
      - [Example of proxy `init.lua`](#example-of-proxy-initlua)
      - [Example of `/etc/proxy/conf.lua`](#example-of-etcproxyconflua)
      - [Example of ETCD configuration (`etcd.instance.single`)](#example-of-etcd-configuration-etcdinstancesingle)
    - [Multi-shard topology for custom sharding (`etcd.cluster.master`)](#multi-shard-topology-for-custom-sharding-etcdclustermaster)
    - [Multi-shard topology for vshard-based applications (`etcd.cluster.vshard`)](#multi-shard-topology-for-vshard-based-applications-etcdclustervshard)
      - [Example of ETCD configuration for vshard-based applications (`etcd.cluster.vshard`)](#example-of-etcd-configuration-for-vshard-based-applications-etcdclustervshard)
      - [Example of vshard-based init.lua (`etcd.cluster.vshard`)](#example-of-vshard-based-initlua-etcdclustervshard)
      - [VShard Maintenance](#vshard-maintenance)

## Status

Ready for production use.

Latest stable release: `config 0.7.2`.

## Installation

```bash
tarantoolctl rocks --server=https://moonlibs.org install config 0.7.2
```

Starting with Tarantool 2.10.0 you may add configuration of moonlibs.org into `config-5.1.lua`

```bash
$ cat .rocks/config-5.1.lua
rocks_servers = {
   "https://moonlibs.org",
   "http://moonlibs.github.io/rocks",
   "http://rocks.tarantool.org/",
   "http://luarocks.org/repositories/rocks"
}
```

## Configuration

To configure tarantool instance you must deploy `conf.lua` file.

### Example of `conf.lua`

Typically conf.lua should be located in `/etc/<app-name>/conf.lua`.

```lua
assert(instance_name, "instance_name must be defined")
etcd = {
    instance_name = instance_name,
    prefix = '/etcd/path/to/application/etcd',
    endpoints = {
        "https://etcd1:2379",
        "https://etcd2:2379",
        "https://etcd3:2379",
    },
    timeout = 3,
    boolean_auto = true,
    print_config = true,
    login = 'etcd-username',
    password = 'etcd-password',
}

-- This options will be passed as is to box.cfg
box = {
    pid_file  = '/var/run/tarantool/'..instance_name..'.pid',
    memtx_dir = '/var/lib/tarantool/snaps/' .. instance_name,
    wal_dir   = '/var/lib/tarantool/xlogs/' .. instance_name,
    log_nonblock = false,
}

--- You may hardcode options for your application in `app` section
app = {

}
```

### Usage in `init.lua`

```lua

local instance_name = os.getenv('TT_INSTANCE_NAME')

require 'config' {
    mkdir = true,
    instance_name = instance_name,
    file = '/etc/<app-name>/conf.lua',
    master_selection_policy = 'etcd.cluster.master',
}

print("Tarantool bootstrapped")
```

## Usage

Module config is used both for bootstrap and configuration of your Tarantool application.

In application you may access config options using following syntax

```lua
local DEFAULT_TIMEOUT = 3

--- If app/http/timeout is defined in config (ETCD or conf.lua) then it will be returned
--- otherwise value of DEFAULT_TIMEUOT will be returned
local http_timeout = config.get('app.http.timeout', DEFAULT_TIMEOUT)

--- If app/is_enabled is not defined then `nil` will be returned.
local is_enabled = config.get('app.is_enabled')
```

## Topologies

`moonlibs/config` supports different types of Tarantool topologies.

All of them make sence when application is configured using ETCD.

To distinguish application topology option `master_selection_policy` is used.

### Single-shard topology

In most cases you need single shard topology. It means, that your application has single master and many replicas.

Shard will be configured with full-mesh topology. Read more about full-mesh topology on [Tarantool website](https://www.tarantool.io/en/doc/latest/concepts/replication/repl_architecture/).

Each instance of application must have unique name. For example:

- `userdb_001`
- `userdb_002`
- `userdb_003`

Typically instance name **should not** contain `master` or `replica` word in it.

#### Example of `init.lua`

```lua
--- variable instance_name must be derived somehow for each tarantool instance
--- For example from name of the file. or from environment variable
require 'config' {
    mkdir = true,
    instance_name = instance_name,
    file = '/etc/userdb/conf.lua',
    master_selection_policy = 'etcd.cluster.master',
}
```

#### Example of `/etc/userdb/conf.lua`

```lua
assert(instance_name, "instance_name must be defined")
etcd = {
    instance_name = instance_name,
    prefix = '/tarantool/userdb',
    endpoints = {
        "https://etcd1:2379",
        "https://etcd2:2379",
        "https://etcd3:2379",
    },
    timeout = 3,
    boolean_auto = true,
    print_config = true,
}

-- This options will be passed as is to box.cfg
box = {
    pid_file  = '/var/run/tarantool/'..instance_name..'.pid',
    memtx_dir = '/var/lib/tarantool/snaps/' .. instance_name,
    wal_dir   = '/var/lib/tarantool/xlogs/' .. instance_name,
    log_nonblock = false,
}
```

#### Example of ETCD configuration (`etcd.cluster.master`)

```yaml
tarantool:
  userdb:
    clusters:
      userdb:
        master: userdb_001
        replicaset_uuid: 045e12d8-0001-0000-0000-000000000000
    common:
      box:
        log_level: 5
        memtx_memory: 268435456
    instances:
      userdb_001:
        cluster: userdb
        box:
          instance_uuid: 045e12d8-0000-0001-0000-000000000000
          listen: 10.0.1.11:3301
      userdb_002:
        cluster: userdb
        box:
          instance_uuid: 045e12d8-0000-0002-0000-000000000000
          listen: 10.0.1.12:3302
      userdb_003:
        cluster: userdb
        box:
          instance_uuid: 045e12d8-0000-0003-0000-000000000000
          listen: 10.0.1.13:3303
```

`/tarantool/userdb` -- is root path for application configuration

`/tarantool/userdb/common` -- is common configuration for each instance of application.

`/tarantool/userdb/common/box` -- is section to configure box.cfg parameters. See more on [Tarantool website](https://www.tarantool.io/en/doc/latest/reference/configuration).

`/tarantool/userdb/clusters` section contains list of shards. For single-shard application it is good to single shard it as application itself.

`/tarantool/userdb/instances` section contains instance-specific configuration. It must contain `/box/{listen,instance_uuid}` and `cluster` options.

##### Configuration precedence

- /etc/app-name/conf.lua
- ETCD:/instances/<instance_name>
- ETCD:/common/
- config.get default value

#### Fencing configuration

`etcd.cluster.master` topology supports auto fencing mechanism.

Auto fencing is implemented via background fiber which waits for changes on `<prefix>/clusters/<my-shard-name>` directory.

`fencing_pause` must be less than `fencing_timeout`. The `fencing_timeout - fencing_pause` time slot is used to retry ETCD (at least 2 attempts with sleeps in between) to ensure that ETCD is really down.

You may increase `fencing_pause` if you see that too many requests is made to ETCD.
If `fencing_timeout - fencing_pause` is too small (less than `etcd/timeout`) then you may face False-Positive fencing when ETCD was slightly down.

Increasing `fencing_timeout` will decrease possibility of False Positive fencing.

You leader will be RW at least `fencing_timeout` if everyone else is down.

There are 4 parameters to configure:

| Parameter                        | Description                           | Default Value       |
|----------------------------------|---------------------------------------|---------------------|
| `etcd/fencing_enabled`           | Trigger to enable/disable fencing     | `false`             |
| `etcd/fencing_timeout`           | Fencing timeout                       | `10` (seconds)      |
| `etcd/fencing_pause`             | Fencing pause                         | `fencing_timeout/2` |
| `etcd/fencing_check_replication` | Respect replication when ETCD is down | `false`             |

Example of enabled fencing:

```yaml
tarantool:
  userdb:
    common:
      etcd:
        fencing_enabled: true
```

Fencing also can be enabled in `conf.lua`:

```lua
etcd = {
    endpoints = {"http://etcd1:2379", "http://etcd2:2379", "http://etcd3:2379"},
    prefix = "/tarantool/userdb",
    timeout = 3,
    fencing_enabled = true,
}
```

#### Fencing algorithm

Fencing can be enabled only for topology `etcd.cluster.master` and only if `etcd/fencing_enabled` is `true` (default: `false`).

Fencing algorithm is the following:

0. Wait until instance became `rw`.
1. Wait randomized `(fencing_timeout - fencing_pause) / 10`.
2. Recheck ETCD `<prefix>/clusters/<my-shard-name>` in `fencing_pause`.
3. Depends on response:
    1. [ETCD is ok] => provision self to be `rw` for next `fencing_timeout` seconds. Go to `1.`
    2. [ETCD is down] => execute `box.cfg{read_only=true}` if `etcd/fencing_check_replication` is disabled. Go to `0.`
    3. [ETCD has another master, and switching in progress] => do nothing. Go to `1.`
    4. [ETCD has another master, and switching is not in progress] => execute `box.cfg{read_only=true}`. Go to `0.`

**Note:** to request ETCD Quorum Reads are used. So it is safe to use it in split brain.

### Operations during disaster

When ETCD failed to determine leader cluster can't reload it's configuration (or restart).

During disaster, you must recovery ETCD elections mechanism first.

If it is not possible, and you need to reload configuration or restart instance you may switch to manual configuration mode.

To do that set `reduce_listing_quorum` to `true` in `conf.lua` config.

After ETCD becames operation you **must** remove this option from local configuration.

```lua
etcd = {
  reduce_listing_quorum = true,
}
```

Enabling this option automatically disables `fencing`.

Be extra careful to not allow Tarantool Master-Master setup. (Since ETCD may have different configuration on it's replicas).

### Multi-proxy topology (etcd.instance.single)

`moonlibs/config` supports multi proxy topology. This topology is usefull when you need to have many stateless tarantool proxies or totally independent masters.

Each instance **should** have unique name. For example:

- proxy_001
- proxy_002
- proxy_003
- proxy_004
- proxy_005

#### Example of proxy `init.lua`

```lua
--- variable instance_name must be derived somehow for each tarantool instance
--- For example from name of the file. or from environment variable
require 'config' {
    mkdir = true,
    instance_name = instance_name,
    file = '/etc/proxy/conf.lua',
    master_selection_policy = 'etcd.instance.single',
}
```

#### Example of `/etc/proxy/conf.lua`

```lua
assert(instance_name, "instance_name must be defined")
etcd = {
    instance_name = instance_name,
    prefix = '/tarantool/proxy',
    endpoints = {
        "https://etcd1:2379",
        "https://etcd2:2379",
        "https://etcd3:2379",
    },
    timeout = 3,
    boolean_auto = true,
    print_config = true,
}

-- This options will be passed as is to box.cfg
box = {
    pid_file  = '/var/run/tarantool/'..instance_name..'.pid',
    memtx_dir = '/var/lib/tarantool/snaps/' .. instance_name,
    wal_dir   = '/var/lib/tarantool/xlogs/' .. instance_name,
    log_nonblock = false,
}
```

#### Example of ETCD configuration (`etcd.instance.single`)

```yaml
tarantool:
  proxy:
    common:
      box:
        log_level: 5
        memtx_memory: 33554432
    instances:
      proxy_001:
        box:
          instance_uuid: 01712087-0000-0001-0000-000000000000
          listen: 10.0.2.12:7101
      proxy_002:
        box:
          instance_uuid: 01712087-0000-0002-0000-000000000000
          listen: 10.0.2.13:7102
      proxy_003:
        box:
          instance_uuid: 01712087-0000-0003-0000-000000000000
          listen: 10.0.2.11:7103
```

The etcd configuration is the same as `etcd.cluster.master` except that `/tarantool/proxy/clusters` is not defined.

Also `/tarantool/proxy/instances/<instance-name>/cluster` **must not** be defined.

### Multi-shard topology for custom sharding (`etcd.cluster.master`)

`etcd.cluster.master` can be used for multi-shard topologies as well.

Multi-shard means that application consists of several replicasets. Each replicaset has single master and several replicas.

`conf.lua` and `init.lua` files remains exactly the same. But configuration of ETCD slightly changes:

```yaml
tarantool:
  notifications:
    clusters:
      notifications_002:
        master: notifications_002_01
        replicaset_uuid: 11079f9c-0002-0000-0000-000000000000
      notifications_001:
        master: notifications_001_01
        replicaset_uuid: 11079f9c-0001-0000-0000-000000000000
    common:
      box:
        log_level: 5
        memtx_memory: 268435456
    instances:
      notifications_001_01:
        cluster: notifications_001
        box:
          instance_uuid: 11079f9c-0001-0001-0000-000000000000
          listen: 10.0.3.11:4011
      notifications_001_02:
        cluster: notifications_001
        box:
          instance_uuid: 11079f9c-0001-0002-0000-000000000000
          listen: 10.0.3.12:4012
      notifications_002_01:
        cluster: notifications_002
        box:
          instance_uuid: 11079f9c-0002-0001-0000-000000000000
          listen: 10.0.3.11:4021
      notifications_002_02:
        cluster: notifications_002
        box:
          instance_uuid: 11079f9c-0002-0002-0000-000000000000
          listen: 10.0.3.12:4022
```

This configuration describes configuration of application `notifications` with 2 replicasets `notifications_001` and `notifications_002`.

Shard `notifications_001` contains 2 nodes:

- `notifications_001_01` - described as master
- `notifications_001_02`

Shard `notifications_002` contains 2 nodes:

- `notifications_002_01` - described as master
- `notifications_002_02`

### Multi-shard topology for vshard-based applications (`etcd.cluster.vshard`)

In most cases for multi-shard applications it is better to use module [tarantool/vshard](https://www.tarantool.io/en/doc/latest/concepts/sharding).

vshard required to be properly configured. Each instance of the cluster must contain the same view of cluster topology.

vshard application has 2 groups of instances: storages (data nodes) and routers (stateless proxy nodes).

#### Example of ETCD configuration for vshard-based applications (`etcd.cluster.vshard`)

```yaml
tarantool:
  profile:
    common:
      vshard:
        bucket_count: 30000
      box:
        log_level: 5
        replication_connect_quorum: 2
    clusters:
      profile_001:
        master: profile_001_01
        replicaset_uuid: 17120f91-0001-0000-0000-000000000000
      profile_002:
        master: profile_002_01
        replicaset_uuid: 17120f91-0002-0000-0000-000000000000
    instances:
      profile_001_01:
        cluster: profile_001
        box:
          instance_uuid: 17120f91-0001-0001-0000-000000000000
          listen: 10.0.4.11:4011
      profile_001_02:
        cluster: profile_001
        box:
          instance_uuid: 17120f91-0001-0002-0000-000000000000
          listen: 10.0.4.12:4012
      profile_002_01:
        cluster: profile_002
        box:
          instance_uuid: 17120f91-0002-0001-0000-000000000000
          listen: 10.0.4.11:4021
      profile_002_02:
        cluster: profile_002
        box:
          instance_uuid: 17120f91-0002-0002-0000-000000000000
          listen: 10.0.4.12:4022
      router_001:
        router: true
        box:
          instance_uuid: 12047e12-0000-0001-0000-000000000000
          listen: 10.0.5.12:7001
      router_002:
        router: true
        box:
          instance_uuid: 12047e12-0000-0002-0000-000000000000
          listen: 10.0.5.13:7002
      router_003:
        router: true
        box:
          instance_uuid: 12047e12-0000-0003-0000-000000000000
          listen: 10.0.5.11:7003
```

#### Example of vshard-based init.lua (`etcd.cluster.vshard`)

The code of simultanious bootstrap is tricky, and short safe version of it listed below

```lua
local fun = require 'fun'
--- variable instance_name must be derived somehow for each tarantool instance
--- For example from name of the file. or from environment variable
require 'config' {
    mkdir = true,
    instance_name = instance_name,
    file  = '/etc/profile/conf.lua',
    master_selection_policy = 'etcd.cluster.vshard',
    on_load = function(conf, cfg)
        -- on_load is called each time right after fetching data from ETCD
        local all_cfg = conf.etcd:get_all()

        -- Construct vshard/sharding table from ETCD
        cfg.sharding = fun.iter(all_cfg.clusters)
            :map(function(shard_name, shard_info)
                return shard_info.replicaset_uuid, {
                    replicas = fun.iter(all_cfg.instances)
                        :grep(function(instance_name, instance_info)
                            return instance_info.cluster == shard_name
                        end)
                        :map(function(instance_name, instance_info)
                            return instance_info.box.instance_uuid, {
                                name   = instance_name,
                                uri    = 'guest:@'..instance_info.box.listen,
                                master = instance_name == shard_info.master,
                            }
                        end)
                        :tomap()
                }
            end)
            :tomap()
    end,
    on_after_cfg = function(conf, cfg)
        -- on_after_cfg is called once after returning from box.cfg (Tarantool is already online)
        if cfg.cluster then
            vshard.storage.cfg({
                sharding = cfg.sharding,
                bucket_count = config.get('vshard.bucket_count'),
            }, box.info.uuid)
        end
        if cfg.router then
            vshard.router.cfg({
                sharding = cfg.sharding,
                bucket_count = config.get('vshard.bucket_count'),
            })
        end
    end,
}
```

#### VShard Maintenance

By default vshard does not support master auto discovery. If you switch master in any replicaset you have to reconfigure routers as well.

With vshard topology it is strongly recommended to use [package.reload](https://github.com/moonlibs/package-reload). Module must be required before first require of `config`.

```lua
require 'package.reload'
-- ....
require 'config' {
    -- ...
}
-- ...
```

It is good to use [switchover](https://gitlab.com/ochaton/switchover) to maintenance sharded applications.

To get used to vshard please read getting started of it [Sharding with Vshard](https://www.tarantool.io/en/doc/latest/book/admin/vshard_admin/#vshard-install)
