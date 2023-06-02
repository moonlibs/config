local t = require 'luatest' --[[@as luatest]]
local uri = require 'uri'
local g = t.group('single')

local this_file = debug.getinfo(1, "S").source:sub(2)
local fio = require 'fio'

local root = fio.dirname(this_file)

local h = require 'spec.helper'
local test_ctx = {}

local working_dir

g.before_each(function()
	working_dir = h.create_workdir()
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

function g.test_single_start()
	test_ctx.single = { tts = {} }

	local etcd_config = {
		apps = {
			single = {
				common = { box = { log_level = 5 } },
				instances = { single = { box = { listen = '127.0.0.1:3301' } } },
			}
		}
	}

	h.upload_to_etcd(etcd_config)

	local env = {
		TT_WAL_DIR = working_dir,
		TT_MEMTX_DIR = working_dir,
		TT_ETCD_PREFIX = '/apps/single',
		TT_INSTANCE_NAME = 'single',
		TT_CONFIG = fio.pathjoin(root, 'mock', 'single', 'conf.lua'),
		TT_MASTER_SELECTION_POLICY = 'etcd.instance.single',
		TT_ETCD_ENDPOINTS = os.getenv('TT_ETCD_ENDPOINTS') or "http://127.0.0.1:2379",
	}

	local init_lua = fio.pathjoin(root, 'mock', 'single', 'init.lua')

	local tt = h.start_tarantool({
		env = env,
		command = init_lua,
		args = {},
		net_box_port = 3301,
	})

	test_ctx.single.tts = {{
		tt = tt,
	}}
	tt:connect_net_box()

	local box_cfg = tt:get_box_cfg()
	t.assert_covers(box_cfg, {
		log_level = 5,
		listen = '127.0.0.1:3301',
	})
end

function g.test_two_singles()
	test_ctx.two_singles = { tts = {}, net_box_ports = {} }

	local etcd_config = {
		apps = {
			single = {
				common = { box = { log_level = 5 } },
				instances = {
					single_01 = { box = { listen = '127.0.0.1:3301' } },
					single_02 = { box = { listen = '127.0.0.1:3302' } },
				},
			}
		}
	}

	h.upload_to_etcd(etcd_config)

	local base_env = {
		TT_WAL_DIR = working_dir,
		TT_MEMTX_DIR = working_dir,
		TT_ETCD_PREFIX = '/apps/single',
		TT_CONFIG = fio.pathjoin(root, 'mock', 'single', 'conf.lua'),
		TT_MASTER_SELECTION_POLICY = 'etcd.instance.single',
		TT_ETCD_ENDPOINTS = os.getenv('TT_ETCD_ENDPOINTS') or "http://127.0.0.1:2379",
	}
	local init_lua = fio.pathjoin(root, 'mock', 'single', 'init.lua')

	for _, name in ipairs{'single_01', 'single_02'} do
		local env = table.deepcopy(base_env)
		env.TT_INSTANCE_NAME = name
		local net_box_port = tonumber(uri.parse(etcd_config.apps.single.instances[name].box.listen).service)

		local tt = h.start_tarantool({
			env = env,
			command = init_lua,
			args = {},
			net_box_port = net_box_port,
		})

		table.insert(test_ctx.two_singles.tts, {
			tt = tt,
			net_box_port = net_box_port,
			env = env,
			name = name,
		})
	end

	for _, tt in ipairs(test_ctx.two_singles.tts) do
		tt.tt:connect_net_box()
		local box_cfg = tt.tt:get_box_cfg()
		t.assert_covers(box_cfg, {
			log_level = 5,
			listen = etcd_config.apps.single.instances[tt.name].box.listen,
		})
	end
end

