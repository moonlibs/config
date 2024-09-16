local t = require 'luatest' --[[@as luatest]]

---@class test.config.single:luatest.group
local g = t.group('single', {
	{ instances = {single = '127.0.0.1:3301'}, run = {'single'} },
	{
		instances = {single_01 = '127.0.0.1:3301', single_02 = '127.0.0.1:3302'},
		run = {'single_01', 'single_02'}
	},
	{
		instances = {single_01 = '127.0.0.1:3301', single_02 = '127.0.0.1:3302'},
		run = {'single_01'}
	},
})

local this_file = debug.getinfo(1, "S").source:sub(2)
local fio = require 'fio'

local root = fio.dirname(this_file)
local init_lua = fio.pathjoin(root, 'mock', 'single', 'init.lua')

local base_env

local h = require 'spec.helper'
local test_ctx = {}

g.before_each(function(cg)
	local working_dir = h.create_workdir()
	base_env = {
		TT_ETCD_PREFIX = '/apps/single',
		TT_CONFIG = fio.pathjoin(root, 'mock', 'single', 'conf.lua'),
		TT_MASTER_SELECTION_POLICY = 'etcd.instance.single',
		TT_ETCD_ENDPOINTS = os.getenv('TT_ETCD_ENDPOINTS') or "http://127.0.0.1:2379",
	}
	base_env.TT_WAL_DIR = working_dir
	base_env.TT_MEMTX_DIR = working_dir
	base_env.TT_WORK_DIR = working_dir

	local base_config = {
		apps = {
			single = {
				common = { box = { log_level = 1 } },
			}
		}
	}
	h.clear_etcd()

	local params = cg.params

	local etcd_config = table.deepcopy(base_config)
	etcd_config.apps.single.instances = {}
	for instance_name, listen_uri in pairs(params.instances) do
		etcd_config.apps.single.instances[instance_name] = { box = { listen = listen_uri } }
	end

	local ctx = { tts = {}, env = base_env, etcd_config = etcd_config, params = cg.params }
	test_ctx[cg.name] = ctx

	h.upload_to_etcd(etcd_config)
end)

g.after_each(function()
	for _, info in pairs(test_ctx) do
		for _, tt in pairs(info.tts) do
			tt.server:stop()
		end
		h.clean_directory(info.env.TT_WAL_DIR)
		h.clean_directory(info.env.TT_MEMTX_DIR)
		h.clean_directory(info.env.TT_WORK_DIR)
	end

	h.clear_etcd()
end)

function g.test_run_instances(cg)
	local ctx = test_ctx[cg.name]

	-- Start tarantools
	h.start_all_tarantools(ctx, init_lua, root, ctx.etcd_config.apps.single.instances)

	for _, tt in ipairs(ctx.tts) do
		tt.server:connect_net_box()
		local box_cfg = tt.server:get_box_cfg()
		t.assert_covers(box_cfg, {
			log_level = ctx.etcd_config.apps.single.common.box.log_level,
			listen = ctx.etcd_config.apps.single.instances[tt.name].box.listen,
			read_only = false,
		}, 'box.cfg is correct')

		local conn = tt.server --[[@as luatest.server]]
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
			instance_name = tt.name,
			master_selection_policy = 'etcd.instance.single',
			file = base_env.TT_CONFIG,
		}, 'get("sys") has correct fields')
	end

	-- restart tarantools
	for _, tt in ipairs(ctx.tts) do
		local conn = tt.server --[[@as luatest.server]]
		h.restart_tarantool(conn)

		local box_cfg = tt.server:get_box_cfg()
		t.assert_covers(box_cfg, {
			log_level = ctx.etcd_config.apps.single.common.box.log_level,
			listen = ctx.etcd_config.apps.single.instances[tt.name].box.listen,
			read_only = false,
		}, 'box.cfg is correct after restart')

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
			instance_name = tt.name,
			master_selection_policy = 'etcd.instance.single',
			file = base_env.TT_CONFIG,
		}, 'get("sys") has correct fields after restart')
	end
end
