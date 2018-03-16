local log = require 'log'
local con = require 'console'
local fiber = require 'fiber'

local keys = {
	box     = true;
	console = true;
	app     = true;
}

local static = {
--- Basic parameters. Not dynamic ---
	work_dir           = true,
	pid_file           = true,
	custom_proc_title  = true,
	username           = true,
	wal_dir            = true,
	snap_dir           = true,
	sophia_dir         = true,
	background         = true,
--- Storage configuration. Not dynamic ---
	slab_alloc_arena   = true,
	slab_alloc_factor  = true,
	slab_alloc_minimal = true,
	slab_alloc_maximal = true,
--- Refactored names. Not dynamic ---
	memtx_memory              = true,
	memtx_max_tuple_size      = true,
	memtx_min_tuple_size      = true,
	memtx_dir                 = true,
	vinyl_dir                 = true,
	vinyl_bloom_fpr           = true,
	vinyl_cache               = true,
	vinyl_memory              = true,
	vinyl_page_size           = true,
	vinyl_range_size          = true,
	vinyl_run_count_per_level = true,
	vinyl_run_size_ratio      = true,
	vinyl_threads             = true,
	vinyl_read_threads        = true,
	vinyl_write_threads       = true,
	sophia             = true,
	-- sophia = {
	-- 	 page_size    = 131072,
	-- 	 threads      = 5,
	-- 	 node_size    = 134217728,
	-- 	 memory_limit = 0,
	-- },
--- Binary logging and snapshots. Not dynamic ---
	panic_on_snap_error  = true,
	rows_per_wal         = true,
	wal_dir_rescan_delay = true,
--- Logging. Not dynamic ---
	logger               = true,
	logger_nonblock      = true,
	log                  = true,
}

local dynamic = {
	read_only           = true,
--- Snapshot daemon. Dynamic ---
	snapshot_period     = true,
	snapshot_count      = true,
--- Refactored names. Dynamic ---
	checkpoint_count    = true,
	checkpoint_interval = true,
--- Binary logging and snapshots. Dynamic ---
	panic_on_wal_error  = true,
	snap_io_rate_limit  = true,
	wal_mode            = true,

--- Replication source. Dynamic ---
	replication_source  = true,
	replication         = true,

--- Networking. Dynamic ---
	listen              = true,
	io_collect_interval = true,
	readahead           = true,
--- Logging. Dynamic ---
	log_level           = true,
	too_long_threshold  = true,
}

local console = {
	listen = true;
}

local function flatten (t,prefix,result)
	prefix = prefix or ''
	result = result or {}
	for k,v in pairs(t) do
		if type(v) == 'table' then
			flatten(v, prefix..k..'.',result)
		end
		result[prefix..k] = v
	end
	return result
end

local M
if rawget(_G,'config') then
	M = rawget(_G,'config')
else
	M = setmetatable({
		console = {};
		get = function(self,k,def)
			if self ~= M then
				def = k
				k = self
			end
			if M.flat[k] ~= nil then
                                return M.flat[k]
                        else
                                return def
                        end
		end
	},{
		__call = function(M,file)
			print("config",M, "loading config ",file)
			if not file then
				local take = false
				local key
				for k,v in ipairs(arg) do
					if take then
						if key == 'config' or key == 'c' then
							file = v
							break
						end
						take = false
					else
						if string.sub( v, 1, 2) == "--" then
							local x = string.find( v, "=", 1, true )
							if x then
								key = string.sub( v, 3, x-1 )
								print("have key=")
								if key == 'config' then
									file = string.sub( v, x+1 )
									break
								end
							else
								print("have key, turn take")
								key = string.sub( v, 3 )
								take = true
							end
						elseif string.sub( v, 1, 1 ) == "-" then
							if string.len(v) == 2 then
								key = string.sub(v,2,2)
								take = true
							else
								key = string.sub(v,2,2)
								if key == 'c' then
									file = string.sub( v, 3 )
									break
								end
							end
						end
					end
				end
				if not file then error("Neither config call option given not -c|--config option passed",2) end
			end
			local f,e = loadfile(file)
			if not f then error(e,2) end
			local cfg = setmetatable({},{__index = _G})
			-- local cfg = setmetatable({},{__index = { print = _G.print, loadstring = _G.loadstring }})
			setfenv(f,cfg)
			f()
			setmetatable(cfg,nil)
			local sttconf = {}
			local dynconf = {}
			local entire_boxconf = {}
			local appconf = {}
			if not cfg.box then
				error("No box.* config given")
			end
			for k,v in pairs(cfg) do
				if not keys[k] then
					log.error("Parameter '%s' = '%s' is not a valid box configuration option.",tostring(k),tostring(v))
					cfg[k] = nil
				end
			end
			for k,v in pairs(cfg.box) do
				if not static[k] and not dynamic[k] then
					log.error("Parameter 'box.%s' = '%s' is not a valid configuration option. Mask it with local, if it's a mistake",tostring(k),tostring(v))
					cfg[k] = nil
				end
				if     static[k]  then sttconf[k] = v
				elseif dynamic[k] then dynconf[k] = v
				else                   appconf[k] = v
				end

				if static[k] or dynamic[k] then
					entire_boxconf[k] = v
				end
			end

			if type(box.cfg) == 'function' then
				-- 1st run
				box.cfg( entire_boxconf )
			else
				for k,v in pairs(sttconf) do
					if box.cfg[k] ~= v then
						log.error("Can't change non-dynamic parameter '%s' from '%s' to '%s'. Restart required",k, box.cfg[k], v)
					end
				end
				box.cfg( dynconf )
			end

			if cfg.console then
				-- print("cfg for ",cfg.console.listen, M.console and M.console.listen)
				for k,v in pairs(cfg.console) do
					if not console[k] then
						log.error("Parameter 'console.%s' = '%s' is not a valid configuration option. Mask it with local, if it's a mistake",tostring(k),tostring(v))
						cfg[k] = nil
					end
				end
				if M.console.listen then
					if M.console.listen ~= cfg.console.listen and M.console.socket then
						-- print("close previoius socket",M.console.listen)
						local r,e = pcall(M.console.socket.close,M.console.socket)
						-- print(r,e)
					end
				end


				local listen = cfg.console.listen
				M.console.listen = listen
				fiber.create(function()
					while M.console.listen == listen do
						local r,e = pcall(con.listen,listen)
						if not r then
							fiber.sleep(1)
						else
							M.console.socket = e
							-- print("console listening on ",cfg.console.listen, e)
							return
						end
					end
				end)
			else
				if M.console.listen then
					-- print("close console socket",M.console.listen)
					local r,e = pcall(M.console.socket.close,M.console.socket)
					print(r,e)
				end
			end
			-- TODO: app conf
			M.flat = flatten(cfg)
			return M
		end
	})
	rawset(_G,'config',M)
end

return M
