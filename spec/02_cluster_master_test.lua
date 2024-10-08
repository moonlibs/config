local t = require 'luatest' --[[@as luatest]]
local uuid = require 'uuid'
local fiber = require 'fiber'

---@class test.config.master:luatest.group
local g = t.group('master', {
	{
		cluster = 'single',
		master = 'first_01',
		instances = {first_01 = '127.0.0.1:3301', first_02 = '127.0.0.1:3302'},
		run = {'first_01', 'first_02'}
	},
	{
		cluster = 'single',
		master = 'second_01',
		instances = {second_01 = '127.0.0.1:3301', second_02 = '127.0.0.1:3302'},
		run = {'second_01'}
	},
	{
		cluster = 'single',
		master = 'third_01',
		instances = {third_01 = '127.0.0.1:3301', third_02 = '127.0.0.1:3302',third_03='127.0.0.1:3303'},
		run = {'third_03','third_02','third_01'}
	},
})

local this_file = debug.getinfo(1, "S").source:sub(2)
local fio = require 'fio'

local root = fio.dirname(this_file)
local init_lua = fio.pathjoin(root, 'mock', 'single', 'init.lua')

local base_env

local h = require 'spec.helper'

---@class moonlibs.config.test.tarantool
---@field server luatest.server
---@field net_box_port number
---@field env table<string,string>
---@field name string

---@class moonlibs.config.test.context
---@field tts moonlibs.config.test.tarantool[]
---@field env table<string,string>
---@field etcd_config table
---@field params table

---@type table<string, moonlibs.config.test.context>
local test_ctx = {}

g.before_each(function(cg)
	local working_dir = h.create_workdir()
	base_env = {
		TT_ETCD_PREFIX = '/apps/single',
		TT_CONFIG = fio.pathjoin(root, 'mock', 'single', 'conf.lua'),
		TT_MASTER_SELECTION_POLICY = 'etcd.cluster.master',
		TT_ETCD_ENDPOINTS = os.getenv('TT_ETCD_ENDPOINTS') or "http://127.0.0.1:2379",
	}

	base_env.TT_WAL_DIR = working_dir
	base_env.TT_MEMTX_DIR = working_dir

	local base_config = {
		apps = {
			single = {
				common = {
					etcd = { fencing_enabled = true },
					box = { log_level = 5 },
				},
				clusters = {
					single = {
						master = cg.params.master,
						replicaset_uuid = uuid.str(),
					}
				},
			}
		},
	}
	h.clear_etcd()

	local etcd_config = table.deepcopy(base_config)
	etcd_config.apps.single.instances = {}
	for instance_name, listen_uri in pairs(cg.params.instances) do
		etcd_config.apps.single.instances[instance_name] = {
			box = { listen = listen_uri },
			cluster = cg.params.cluster,
		}
	end

	local this_ctx = { tts = {}, env = base_env, etcd_config = etcd_config, params = cg.params }
	test_ctx[cg.name] = this_ctx

	h.upload_to_etcd(etcd_config)
end)

g.after_each(function()
	for _, info in pairs(test_ctx) do
		for _, tt in pairs(info.tts) do
			tt.server:stop()
		end
		h.clean_directory(info.env.TT_WAL_DIR)
		h.clean_directory(info.env.TT_MEMTX_DIR)
	end

	h.clear_etcd()
end)

function g.test_run_instances(cg)
	local ctx = test_ctx[cg.name]

	-- Start tarantools
	h.start_all_tarantools(ctx, init_lua, root, ctx.etcd_config.apps.single.instances)

	-- Check configuration
	for _, tnt in ipairs(ctx.tts) do
		tnt.server:connect_net_box()
		local box_cfg = tnt.server:get_box_cfg()
		t.assert_covers(box_cfg, {
			log_level = ctx.etcd_config.apps.single.common.box.log_level,
			listen = ctx.etcd_config.apps.single.instances[tnt.name].box.listen,
			read_only = ctx.etcd_config.apps.single.clusters.single.master ~= tnt.name,
		}, 'box.cfg is correct')

		local conn = tnt.server --[[@as luatest.server]]
		local ret = conn:exec(function()
			local r = table.deepcopy(config.get('sys'))
			for k, v in pairs(r) do
				if type(v) == 'function' then
					r[k] = nil
				end
			end
			return r
		end)

		t.assert_covers(ret, {
			instance_name = tnt.name,
			master_selection_policy = 'etcd.cluster.master',
			file = base_env.TT_CONFIG,
		}, 'get("sys") has correct fields')
	end

	-- restart+check configuration
	for _, tt in ipairs(ctx.tts) do
		h.restart_tarantool(tt.server)

		local box_cfg = tt.server:get_box_cfg()
		t.assert_covers(box_cfg, {
			log_level = ctx.etcd_config.apps.single.common.box.log_level,
			listen = ctx.etcd_config.apps.single.instances[tt.name].box.listen,
			read_only = ctx.etcd_config.apps.single.clusters.single.master ~= tt.name,
		}, 'box.cfg is correct after restart')

		local ret = tt.server:exec(function()
			local r = table.deepcopy(config.get('sys'))
			for k, v in pairs(r) do
				if type(v) == 'function' then
					r[k] = nil
				end
			end
			return r
		end)

		t.assert_covers(ret, {
			instance_name = tt.name,
			master_selection_policy = 'etcd.cluster.master',
			file = base_env.TT_CONFIG,
		}, 'get("sys") has correct fields after restart')
	end
end

function g.test_reload(cg)
	local ctx = test_ctx[cg.name]

	-- Start tarantools
	h.start_all_tarantools(ctx, init_lua, root, ctx.etcd_config.apps.single.instances)

	-- reload+check configuration
	for _, tt in ipairs(ctx.tts) do
		h.reload_tarantool(tt.server)

		local box_cfg = tt.server:get_box_cfg()
		t.assert_covers(box_cfg, {
			log_level = ctx.etcd_config.apps.single.common.box.log_level,
			listen = ctx.etcd_config.apps.single.instances[tt.name].box.listen,
			read_only = ctx.etcd_config.apps.single.clusters.single.master ~= tt.name,
		}, 'box.cfg is correct after restart')

		local ret = tt.server:exec(function()
			local r = table.deepcopy(config.get('sys'))
			for k, v in pairs(r) do
				if type(v) == 'function' then
					r[k] = nil
				end
			end
			return r
		end)

		t.assert_covers(ret, {
			instance_name = tt.name,
			master_selection_policy = 'etcd.cluster.master',
			file = base_env.TT_CONFIG,
		}, 'get("sys") has correct fields after restart')
	end
end

function g.test_fencing(cg)
	local ctx = test_ctx[cg.name]
	t.skip_if(not ctx.etcd_config.apps.single.common.etcd.fencing_enabled, "fencing disabled")

	-- Start tarantools
	h.start_all_tarantools(ctx, init_lua, root, ctx.etcd_config.apps.single.instances)

	-- Check configuration
	for _, tnt in ipairs(ctx.tts) do
		tnt.server:connect_net_box()
		local box_cfg = tnt.server:get_box_cfg()
		t.assert_covers(box_cfg, {
			log_level = ctx.etcd_config.apps.single.common.box.log_level,
			listen = ctx.etcd_config.apps.single.instances[tnt.name].box.listen,
			read_only = ctx.etcd_config.apps.single.clusters.single.master ~= tnt.name,
		}, 'box.cfg is correct')

		local conn = tnt.server --[[@as luatest.server]]
		local ret = conn:exec(function()
			local r = table.deepcopy(config.get('sys'))
			for k, v in pairs(r) do
				if type(v) == 'function' then
					r[k] = nil
				end
			end
			return r
		end)

		t.assert_covers(ret, {
			instance_name = tnt.name,
			master_selection_policy = 'etcd.cluster.master',
			file = base_env.TT_CONFIG,
		}, 'get("sys") has correct fields')
	end

	local master_name = ctx.params.master

	---@type moonlibs.config.test.tarantool
	local master
	for _, tt in ipairs(ctx.tts) do
		if tt.name == master_name then
			master = tt
			break
		end
	end

	t.assert(master, 'master is not connected')

	local ret = master.server:exec(function()
		return { cfg_ro = box.cfg.read_only, ro = box.info.ro }
	end)

	t.assert_equals(ret.cfg_ro, false, 'box.cfg.read_only == false (before fencing)')
	t.assert_equals(ret.ro, false, 'box.info.ro == false (before fencing)')

	ctx.etcd_config.apps.single.clusters.single.master = 'not_exists'
	h.upload_to_etcd(ctx.etcd_config)

	local fencing_cfg = ctx.etcd_config.apps.single.common.etcd
	local fencing_timeout = fencing_cfg.fencing_timeout or 10
	local fencing_pause = fencing_cfg.fencing_pause or fencing_timeout/2

	t.helpers.retrying({
		timeout = fencing_pause,
		delay = 0.1,
	}, function ()
		local ret = master.server:exec(function()
			return { cfg_ro = box.cfg.read_only, ro = box.info.ro }
		end)
		assert(ret.cfg_ro, "cfg.read_only must be true")
		assert(ret.ro, "info.ro must be true")
	end)

	local ret = master.server:exec(function()
		return { cfg_ro = box.cfg.read_only, ro = box.info.ro }
	end)

	t.assert_equals(ret.cfg_ro, true, 'box.cfg.read_only == true')
	t.assert_equals(ret.ro, true, 'box.info.ro == true')

	ctx.etcd_config.apps.single.clusters.single.master = master_name
	h.upload_to_etcd(ctx.etcd_config)

	local deadline = 2*fencing_timeout+fiber.time()
	while fiber.time() < deadline do
		local ret2 = master.server:exec(function()
			return { cfg_ro = box.cfg.read_only, ro = box.info.ro }
		end)

		t.assert_equals(ret2.cfg_ro, true, 'box.cfg.read_only == true (double check)')
		t.assert_equals(ret2.ro, true, 'box.info.ro == true (double check)')
	end
end
