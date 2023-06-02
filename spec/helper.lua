local h = {}
local t = require 'luatest' --[[@as luatest]]
local fio = require 'fio'
local log = require 'log'
local fun = require 'fun'
local clock = require 'clock'
local fiber = require 'fiber'
local http = require 'http.client'
local json = require 'json'

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
	assert(res.status >= 200 and res.status < 300, ("%s %s"):format(res.status, res.body))
end

function h.upload_to_etcd(tree)
	local etcd = h.get_etcd()

	local flat = flatten(tree)
	local keys = fun.totable(flat)
	table.sort(keys)
	for _, key in ipairs(keys) do
		do
			local _, res = etcd:request('PUT', 'keys'..key, { value = flat[key] })
			log.info(res)
			assert(res.status < 300 and res.status >= 200, res.reason)
		end
	end

	local key = keys[1]:match('^(/[^/]+)')
	log.info((etcd:list(key)))
end

---Starts new tarantool server
---@param opts luatest.server.options
---@return luatest.server
function h.start_tarantool(opts)
	log.info(opts)
	local srv = t.Server:new(opts)
	srv:start()

	local process = srv.process

	local deadline = clock.time() + 15
	while clock.time() < deadline do
		fiber.sleep(3)
		assert(process:is_alive(), "tarantool is dead")

		if pcall(function() srv:connect_net_box() end) then
			break
		end
	end

	return srv
end


return h
