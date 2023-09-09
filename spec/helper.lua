local h = {}
local t = require 'luatest' --[[@as luatest]]
local fio = require 'fio'
local log = require 'log'
local uri = require 'uri'
local fun = require 'fun'
local clock = require 'clock'
local fiber = require 'fiber'
local json  = require 'json'

---Creates temporary working directory
---@return string
function h.create_workdir()
	local tempdir = fio.tempdir()
	assert(fio.mktree(tempdir))

	return tempdir
end

---Removes all data in the path
---@param path string
function h.clean_directory(path)
	if fio.path.is_dir(path) then
		assert(fio.rmtree(path))
	elseif fio.path.is_file(path) then
		assert(fio.unlink(path))
	end
end

---@param tree table
---@param path string?
---@param ret table<string,string|number|boolean>?
---@return table<string,string|number|boolean>
local function flatten(tree, path, ret)
	path = path or ''
	---@type table<string, string|number|boolean>
	ret = ret or {}
	for key, sub in pairs(tree) do
		local base_type = type(sub)
		if base_type ~= 'table' then
			ret[path..'/'..key] = tostring(sub)
		else
			flatten(sub, path .. '/' .. key, ret)
		end
	end
	return ret
end

---comment
---@return EtcdCfg
function h.get_etcd()
	local endpoints = (os.getenv('TT_ETCD_ENDPOINTS') or "http://127.0.0.1:2379")
		:gsub(",+", ",")
		:gsub(',$','')
		:split(',')

	local etcd = require 'config.etcd':new{
		endpoints = endpoints,
		prefix = '/',
		debug = true,
	}

	t.helpers.retrying({ timeout = 5 }, function() etcd:discovery() end)

	return etcd
end

function h.clear_etcd()
	local etcd = h.get_etcd()

	local _, res = etcd:request('DELETE', 'keys/apps', { recursive = true, dir = true, force = true })
	log.info("clear_etcd(%s) => %s:%s", '/apps', res.status, res.reason)
	assert(res.status >= 200 and(res.status < 300 or res.status == 404), ("%s %s"):format(res.status, res.body))
end

function h.upload_to_etcd(tree)
	local etcd = h.get_etcd()

	local flat = flatten(tree)
	local keys = fun.totable(flat)
	table.sort(keys)
	for _, key in ipairs(keys) do
		do
			local _, res = etcd:request('PUT', 'keys'..key, { value = flat[key], quorum = true })
			assert(res.status < 300 and res.status >= 200, res.reason)
		end
	end

	local key = keys[1]:match('^(/[^/]+)')
	log.info("list(%s): => %s", key, json.encode(etcd:list(key)))
end

---Starts new tarantool server
---@param opts luatest.server.options
---@return luatest.server
function h.start_tarantool(opts)
	log.info("starting tarantool %s", json.encode(opts))
	local srv = t.Server:new(opts)
	srv:start()

	local process = srv.process

	local deadline = clock.time() + 30
	while clock.time() < deadline do
		fiber.sleep(0.1)
		if process:is_alive() then break end
	end
	return srv
end

function h.start_all_tarantools(ctx, init_lua, root, instances)
	for _, name in ipairs(ctx.params.run) do
		local env = table.deepcopy(ctx.env)
		env.TT_INSTANCE_NAME = name
		local net_box_port = tonumber(uri.parse(instances[name].box.listen).service)

		local tt = h.start_tarantool({
			alias = name,
			env = env,
			command = init_lua,
			args = {},
			net_box_port = net_box_port,
			workdir = root,
		})

		table.insert(ctx.tts, {
			server = tt,
			net_box_port = net_box_port,
			env = env,
			name = name,
		})
	end

	for _, tt in ipairs(ctx.tts) do
		h.wait_tarantool(tt.server)
	end
end

---@param srv luatest.server
function h.wait_tarantool(srv)
	t.helpers.retrying({ timeout = 30, delay = 0.1 }, function ()
		srv:connect_net_box()
		srv:call('box.info')
	end)
end

---@param server luatest.server
function h.restart_tarantool(server)
	server:stop()
	local deadline = clock.time() + 15

	fiber.sleep(3)
	server:start()

	while clock.time() < deadline do
		fiber.sleep(3)
		assert(server.process:is_alive(), "tarantool is dead")

		if pcall(function() server:connect_net_box() end) then
			break
		end

	end
end

---@param server luatest.server
function h.reload_tarantool(server)
	server:exec(function()
		package.reload()
	end)
end


return h
