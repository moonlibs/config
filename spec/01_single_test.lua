local t = require 'luatest' --[[@as luatest]]
local uri = require 'uri'

local base_config = {
	apps = {
		single = {
			common = { box = { log_level = 4 } },
		}
	}
}

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

local base_env = {
	TT_WAL_DIR = nil, -- will be set at before_each trigger
	TT_MEMTX_DIR = nil,  -- will be set at before_each trigger
	TT_ETCD_PREFIX = '/apps/single',
	TT_CONFIG = fio.pathjoin(root, 'mock', 'single', 'conf.lua'),
	TT_MASTER_SELECTION_POLICY = 'etcd.instance.single',
	TT_ETCD_ENDPOINTS = os.getenv('TT_ETCD_ENDPOINTS') or "http://127.0.0.1:2379",
}

local h = require 'spec.helper'
local test_ctx = {}

local working_dir

g.before_each(function()
	working_dir = h.create_workdir()
	base_env.TT_WAL_DIR = working_dir
	base_env.TT_MEMTX_DIR = working_dir
end)

g.after_each(function()
	for _, info in pairs(test_ctx) do
		for _, tt in pairs(info.tts) do
			tt.tt:stop()
		end
	end

	h.clean_directory(working_dir)
	h.clear_etcd()
end)

function g.test_run_instances(cg)
	local params = cg.params
	local this_ctx = { tts = {} }
	test_ctx[cg.name] = this_ctx

	local etcd_config = table.deepcopy(base_config)
	etcd_config.apps.single.instances = {}
	for instance_name, listen_uri in pairs(params.instances) do
		etcd_config.apps.single.instances[instance_name] = { box = { listen = listen_uri } }
	end

	h.upload_to_etcd(etcd_config)

	for _, name in ipairs(params.run) do
		local env = table.deepcopy(base_env)
		env.TT_INSTANCE_NAME = name
		local net_box_port = tonumber(uri.parse(etcd_config.apps.single.instances[name].box.listen).service)

		local tt = h.start_tarantool({
			env = env,
			command = init_lua,
			args = {},
			net_box_port = net_box_port,
		})

		table.insert(this_ctx.tts, {
			tt = tt,
			net_box_port = net_box_port,
			env = env,
			name = name,
		})
	end

	for _, tt in ipairs(this_ctx.tts) do
		tt.tt:connect_net_box()
		local box_cfg = tt.tt:get_box_cfg()
		t.assert_covers(box_cfg, {
			log_level = etcd_config.apps.single.common.box.log_level,
			listen = etcd_config.apps.single.instances[tt.name].box.listen,
			read_only = false,
		}, 'box.cfg is correct')

		local conn = tt.tt --[[@as luatest.server]]
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

	for _, tt in ipairs(this_ctx.tts) do
		local conn = tt.tt --[[@as luatest.server]]
		h.restart_tarantool(conn)

		local box_cfg = tt.tt:get_box_cfg()
		t.assert_covers(box_cfg, {
			log_level = etcd_config.apps.single.common.box.log_level,
			listen = etcd_config.apps.single.instances[tt.name].box.listen,
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
