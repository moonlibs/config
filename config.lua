local log = require 'log'
local fio = require 'fio'
local json = require 'json'
local yaml = require 'yaml'
local digest = require 'digest'
json.cfg{ encode_invalid_as_nil = true }

local function lookaround(fun)
	local vars = {}
	local i = 1
	while true do
		local n,v = debug.getupvalue(fun,i)
		if not n then break end
		vars[n] = v
		i = i + 1
	end
	i = 1

	return vars, i - 1
end

local function peek_vars()
	local peek = {
		dynamic_cfg   = true;
		upgrade_cfg   = true;
		translate_cfg = true;
		template_cfg  = true;
		log           = true;
	}

	local steps = {}
	local peekf = box.cfg
	local allow_ctl_unwrap = true
	while true do
		local prevf = peekf
		local mt = debug.getmetatable(peekf)
		if type(peekf) == 'function' then
			-- pass
			table.insert(steps,"func")
		elseif mt and mt.__call then
			peekf = mt.__call
			table.insert(steps,"mt_call")
		else
			error(string.format("Neither function nor callable argument %s after steps: %s", peekf, table.concat(steps, ", ")))
		end

		local vars, _ = lookaround(peekf)
		if allow_ctl_unwrap and vars.orig_cfg then
			-- It's a wrap of tarantoolctl, unwrap and repeat
			peekf = vars.orig_cfg
			allow_ctl_unwrap = false
			table.insert(steps,"ctl-orig")
		elseif not vars.dynamic_cfg and vars.lock and vars.f and type(vars.f) == 'function' then
			peekf = vars.f
			table.insert(steps,"lock-unwrap")
		elseif not vars.dynamic_cfg and vars.old_call and type(vars.old_call) == 'function' then
			peekf = vars.old_call
			table.insert(steps,"ctl-oldcall")
		elseif not vars.dynamic_cfg and vars.orig_cfg_call and type(vars.orig_cfg_call) == 'function' then
			peekf = vars.orig_cfg_call
			table.insert(steps,"ctl-orig_cfg_call")
		elseif vars.dynamic_cfg then
			log.info("Found config by steps: %s", table.concat(steps, ", "))
			for k in pairs(peek) do
				if vars[k] ~= nil then
					peek[k] = vars[k]
				else
					peek[k] = nil
				end
			end
			break
		else
			for k,v in pairs(vars) do log.info("var %s=%s",k,v) end
			error(string.format("Bad vars for %s after steps: %s", peekf, table.concat(steps, ", ")))
		end
		if prevf == peekf then
			error(string.format("Recursion for %s after steps: %s", peekf, table.concat(steps, ", ")))
		end
	end
	return peek
end

local peek = peek_vars()

-- TODO: suppress deprecation
local function prepare_box_cfg(cfg)
	-- 1. take config, if have upgrade, upgrade it
	if peek.upgrade_cfg then
		cfg = peek.upgrade_cfg(cfg, peek.translate_cfg)
	end

	-- 2. check non-dynamic, and wipe them out
	if type(box.cfg) ~= 'function' then
		for key, val in pairs(cfg) do
			if peek.dynamic_cfg[key] == nil and box.cfg[key] ~= val then
				local warn = string.format(
					"Can't change option '%s' dynamically from '%s' to '%s'",
					key,box.cfg[key],val
				)
				log.warn("%s",warn)
				print(warn)
				cfg[key] = nil
			end
		end
	end

	return cfg
end

local readonly_mt = {
	__index = function(_,k) return rawget(_,k) end;
	__newindex = function(_,k)
		error("Modification of readonly key "..tostring(k),2)
	end;
	__serialize = function(_)
		local t = {}
		for k,v in pairs(_) do
			t[k]=v
		end
		return t
	end;
}

local function flatten (t,prefix,result)
	prefix = prefix or ''
	local protect = not result
	result = result or {}
	for k,v in pairs(t) do
		if type(v) == 'table' then
			flatten(v, prefix..k..'.',result)
		end
		result[prefix..k] = v
	end
	if protect then
		return setmetatable(result,readonly_mt)
	end
	return result
end

local function get_opt()
	local take = false
	local key
	for _,v in ipairs(arg) do
		if take then
			if key == 'config' or key == 'c' then
				return v
			end
		else
			if string.sub( v, 1, 2) == "--" then
				local x = string.find( v, "=", 1, true )
				if x then
					key = string.sub( v, 3, x-1 )
					-- print("have key=")
					if key == 'config' then
						return string.sub( v, x+1 )
					end
				else
					-- print("have key, turn take")
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
						return string.sub( v, 3 )
					end
				end
			end
		end
	end
end

local function deep_merge(dst,src,keep)
	-- TODO: think of cyclic
	if not src or not dst then error("Call to deepmerge with bad args",2) end
	for k,v in pairs(src) do
		if type(v) == 'table' then
			if not dst[k] then dst[k] = {} end
			deep_merge(dst[k],src[k],keep)
		else
			if dst[k] == nil or not keep then
				dst[k] = src[k]
			end
		end
	end
end

local function deep_copy(src)
	local t = {}
	deep_merge(t, src)
	return t
end

local function is_array(a)
	local len = 0
	for k in pairs(a) do
		len = len + 1
		if type(k) ~= 'number' then
			return false
		end
	end
	return #a == len
end

--[[
	returns config diff
	1. deleted values returned as box.NULL
	2. arrays is replaced completely
	3. nil means no diff (and not stored in tables)
]]

local function value_diff(old,new)
	if type(old) ~= type(new) then
		return new
	elseif type(old) == 'table' then
		if new == old then return end

		if is_array(old) then
			if #new ~= #old then return new end
			for i = 1,#old do
				local diff = value_diff(old[i], new[i])
				if diff ~= nil then
					return new
				end
			end
		else
			local diff = {}
			for k in pairs(old) do
				if new[ k ] == nil then
					diff[k] = box.NULL
				else
					local vdiff = value_diff(old[k], new[k])
					if vdiff ~= nil then
						diff[k] = vdiff
					end
				end
			end
			for k in pairs(new) do
				if old[ k ] == nil then
					diff[k] = new[k]
				end
			end
			if next(diff) then
				return diff
			end
		end
	else
		if old ~= new then
			return new
		end
	end
	return -- no diff
end

local function toboolean(v)
	if v then
		if type(v) == 'boolean' then return v end
		v = tostring(v):lower()
		local n = tonumber(v)
		if n then return n ~= 0 end
		if v == 'true' or v == 'yes' then
			return true
		end
	end
	return false
end

local master_selection_policies;
master_selection_policies = {
	['etcd.instance.single'] = function(_, _, common_cfg, instance_cfg, cluster_cfg, local_cfg)
		local cfg = {}
		deep_merge(cfg, common_cfg)
		deep_merge(cfg, instance_cfg)

		if cluster_cfg then
			error("Cluster config should not exist for single instance config")
		end

		deep_merge(cfg, local_cfg)

		if cfg.box.read_only == nil then
			log.info("Instance have no read_only option, set read_only=false")
			cfg.box.read_only = false
		end

		if cfg.box.instance_uuid and not cfg.box.replicaset_uuid then
			cfg.box.replicaset_uuid = cfg.box.instance_uuid
		end

		log.info("Using policy etcd.instance.single, read_only=%s",cfg.box.read_only)
		return cfg
	end;
	['etcd.instance.read_only'] = function(M, _, common_cfg, instance_cfg, cluster_cfg, local_cfg)
		local cfg = {}
		deep_merge(cfg, common_cfg)
		deep_merge(cfg, instance_cfg)

		if cluster_cfg then
			log.info("cluster=%s",json.encode(cluster_cfg))
			assert(cluster_cfg.replicaset_uuid,"Need cluster uuid")
			cfg.box.replicaset_uuid = cluster_cfg.replicaset_uuid
		end

		deep_merge(cfg, local_cfg)

		if M.default_read_only and cfg.box.read_only == nil then
			log.info("Instance have no read_only option, set read_only=true")
			cfg.box.read_only = true
		end

		log.info("Using policy etcd.instance.read_only, read_only=%s",cfg.box.read_only)
		return cfg
	end;
	['etcd.cluster.master'] = function(_, instance_name, common_cfg, instance_cfg, cluster_cfg, local_cfg)
		log.info("Using policy etcd.cluster.master")
		local cfg = {}
		deep_merge(cfg, common_cfg)
		deep_merge(cfg, instance_cfg)

		assert(cluster_cfg.replicaset_uuid,"Need cluster uuid")
		cfg.box.replicaset_uuid = cluster_cfg.replicaset_uuid

		if cfg.box.read_only ~= nil then
			log.info("Ignore box.read_only=%s value due to config policy",cfg.box.read_only)
		end
		if cluster_cfg.master then
			if cluster_cfg.master == instance_name then
				log.info("Instance is declared as cluster master, set read_only=false")
				cfg.box.read_only = false
			else
				log.info("Cluster has another master %s, not me %s, set read_only=true", cluster_cfg.master, instance_name)
				cfg.box.read_only = true
			end
		else
			log.info("Claster have no declared master, set read_only=true")
			cfg.box.read_only = true
		end

		deep_merge(cfg, local_cfg)

		return cfg
	end;
	['etcd.cluster.vshard'] = function(M, instance_name, common_cfg, instance_cfg, cluster_cfg, local_cfg)
		log.info("Using policy etcd.cluster.vshard")
		if instance_cfg.cluster then
			return master_selection_policies['etcd.cluster.master'](M, instance_name, common_cfg, instance_cfg, cluster_cfg, local_cfg)
		else
			return master_selection_policies['etcd.instance.single'](M, instance_name, common_cfg, instance_cfg, cluster_cfg, local_cfg)
		end
	end;
	['etcd.cluster.raft'] = function(M, instance_name, common_cfg, instance_cfg, cluster_cfg, local_cfg)
		log.info("Using policy etcd.cluster.raft")
		local cfg = {}
		deep_merge(cfg, common_cfg)
		deep_merge(cfg, instance_cfg)

		assert(cluster_cfg.replicaset_uuid,"Need cluster uuid")
		cfg.box.replicaset_uuid = cluster_cfg.replicaset_uuid

		if cfg.box.election_mode == 'off' or cfg.box.election_mode == nil then
			log.info("Force box.read_only=true for election_mode=off")
			cfg.box.read_only = true
		end

		if not cfg.box.election_mode then
			cfg.box.election_mode = M.default_election_mode
		end
		if not cfg.box.replication_synchro_quorum then
			cfg.box.replication_synchro_quorum = M.default_synchro_quorum
		end

		deep_merge(cfg, local_cfg)

		return cfg
	end;
}

local function cast_types(c)
	if c then
		for k,v in pairs(c) do
			if peek.template_cfg[k] == 'boolean' and type(v) == 'string' then
				c[k] = c[k] == 'true'
			end
		end
	end
end

local function gen_instance_uuid(instance_name)
	local k,d1,d2 = instance_name:match("^([A-Za-z_]+)_(%d+)_(%d+)$")
	if k then
		return string.format(
			"%08s-%04d-%04d-%04d-%012x",
			digest.sha1_hex(k .. "_instance"):sub(1,8),
			d1,d2,0,0
		)
	end

	k,d1 = instance_name:match("^([A-Za-z_]+)_(%d+)$")
	if k then
		return string.format(
			"%08s-%04d-%04d-%04d-%012d",
			digest.sha1_hex(k):sub(1,8),
			0,0,0,d1
		)
	end
	error("Can't generate uuid for instance "..instance_name, 2)
end

local function gen_cluster_uuid(cluster_name)
	local k,d1 = cluster_name:match("^([A-Za-z_]+)_(%d+)$")
	if k then
		return string.format(
			"%08s-%04d-%04d-%04d-%012d",
			digest.sha1_hex(k .. "_shard"):sub(1,8),
			d1,0,0,0
		)
	end
	error("Can't generate uuid for instance "..cluster_name, 2)
end

local function etcd_load( M, etcd_conf, local_cfg )

	local etcd
	local instance_name = assert(etcd_conf.instance_name,"etcd.instance_name is required")
	local prefix = assert(etcd_conf.prefix,"etcd.prefix is required")

	if etcd_conf.fixed then
		etcd = setmetatable({ data = etcd_conf.fixed },{__index = {
			discovery = function() end;
			list = function(e,k)
				if k:sub(1,#prefix) == prefix then
					k = k:sub(#prefix + 1)
				end
				local v = e.data
				for key in k:gmatch("([^/]+)") do
					if type(v) ~= "table" then return end
					v = v[key]
				end
				return v
			end;
		}})
	else
		etcd = require 'config.etcd' (etcd_conf)
	end
	M.etcd = etcd

	function M.etcd.get_common(e)
		local common_cfg = e:list(prefix .. "/common")
		assert(common_cfg.box,"no box config in etcd common tree")
		cast_types(common_cfg.box)
		return common_cfg
	end

	function M.etcd.get_instances(e)
		local all_instances_cfg = e:list(prefix .. "/instances")
		for instance_name,inst_cfg in pairs(all_instances_cfg) do
			cast_types(inst_cfg.box)
			if etcd_conf.uuid == 'auto' and not inst_cfg.box.instance_uuid then
				inst_cfg.box.instance_uuid = gen_instance_uuid(instance_name)
			end
		end
		return all_instances_cfg
	end

	function M.etcd.get_clusters(e)
		local all_clusters_cfg = e:list(prefix .. "/clusters") or etcd:list(prefix .. "/shards")
		for cluster_name,cluster_cfg in pairs(all_clusters_cfg) do
			cast_types(cluster_cfg)
			if etcd_conf.uuid == 'auto' and not cluster_cfg.replicaset_uuid then
				cluster_cfg.replicaset_uuid = gen_cluster_uuid(cluster_name)
			end
		end
		return all_clusters_cfg
	end

	function M.etcd.get_all(e)
		local all_cfg = e:list(prefix)
		cast_types(all_cfg.common.box)
		for instance_name,inst_cfg in pairs(all_cfg.instances) do
			cast_types(inst_cfg.box)
			if etcd_conf.uuid == 'auto' and not inst_cfg.box.instance_uuid then
				inst_cfg.box.instance_uuid = gen_instance_uuid(instance_name)
			end
		end
		for cluster_name,cluster_cfg in pairs(all_cfg.clusters or all_cfg.shards or {}) do
			cast_types(cluster_cfg)
			if etcd_conf.uuid == 'auto' and not cluster_cfg.replicaset_uuid then
				cluster_cfg.replicaset_uuid = gen_cluster_uuid(cluster_name)
			end
		end
		return all_cfg
	end

	etcd:discovery()

	local all_cfg = etcd:get_all()
	if etcd_conf.print_config then
		print("Loaded config from etcd",yaml.encode(all_cfg))
	end
	local common_cfg = all_cfg.common
	-- local common_cfg = etcd:get_common()
	local all_instances_cfg = all_cfg.instances
	-- local all_instances_cfg = etcd:get_instances()

	local instance_cfg = all_instances_cfg[instance_name]
	assert(instance_cfg,"Instance name "..instance_name.." is not known to etcd")

	-- local all_clusters_cfg = etcd:get_clusters()
	local all_clusters_cfg = all_cfg.clusters or all_cfg.shards

	-- print(yaml.encode(all_clusters_cfg))


	local master_selection_policy
	local cluster_cfg
	if instance_cfg.cluster or local_cfg.cluster then
		cluster_cfg = all_clusters_cfg[ (instance_cfg.cluster or local_cfg.cluster) ]
		assert(cluster_cfg,"Cluster section required");
		assert(cluster_cfg.replicaset_uuid,"Need cluster uuid")
		master_selection_policy = M.master_selection_policy or 'etcd.instance.read_only'
	elseif instance_cfg.router then
		-- TODO
		master_selection_policy = M.master_selection_policy or 'etcd.instance.single'
	else
		master_selection_policy = M.master_selection_policy or 'etcd.instance.single'
	end

	local master_policy = master_selection_policies[ master_selection_policy ]
	if not master_policy then
		error(string.format("Unknown master_selection_policy: %s",M.master_selection_policy),0)
	end

	local cfg = master_policy(M, instance_name, common_cfg, instance_cfg, cluster_cfg, local_cfg)

	local members = {}
	for _,v in pairs(all_instances_cfg) do
		if v.cluster == cfg.cluster then -- and k ~= instance_name then
			if not toboolean(v.disabled) then
				table.insert(members,v)
			else
				log.warn("Member '%s' from cluster '%s' listening on %s is disabled", instance_name, v.cluster, v.box.listen)
			end
		end
	end

	if cfg.cluster then
		--if cfg.box.read_only then
			local repl = {}
			for _,member in pairs(members) do
				if member.box.remote_addr then
					table.insert(repl, member.box.remote_addr)
				else
					table.insert(repl, member.box.listen)
				end
			end
			table.sort(repl, function(a,b)
				local ha,pa = a:match('^([^:]+):(.+)')
				local hb,pb = a:match('^([^:]+):(.+)')
				if pa and pb then
					if pa < pb then return true end
					if ha < hb then return true end
				end
				return a < b
			end)
			if cfg.box.replication then
				print(
					"Start instance ",cfg.box.listen,
					" with locally overriden replication:",table.concat(cfg.box.replication,", "),
					" instead of etcd's:", table.concat(repl,", ")
				)
			else
				cfg.box.replication = repl
				print(
					"Start instance "..cfg.box.listen,
					" with replication:"..table.concat(cfg.box.replication,", "),
					string.format("timeout: %s, quorum: %s, lag: %s",
						cfg.box.replication_connect_timeout or 'def:30',
						cfg.box.replication_connect_quorum or 'def:full',
						cfg.box.replication_sync_lag or 'def:10'
					)
				)
			end

		--end
	end
	-- print(yaml.encode(cfg))

	return cfg
end

local function is_replication_changed (old_conf, new_conf)
	if type(old_conf) == 'table' and type(new_conf) == 'table' then
		local changed_replicas = {}
		for _, replica in pairs(old_conf) do
			changed_replicas[replica] = true
		end

		for _, replica in pairs(new_conf) do
			if changed_replicas[replica] then
				changed_replicas[replica] = nil
			else
				return true
			end
		end

		-- if we have some changed_replicas left, then we definitely need to reconnect
		return not not next(changed_replicas)
	else
		return old_conf ~= new_conf
	end
end

local M
	M = setmetatable({
		console = {};
		get = function(self,k,def)
			if self ~= M then
				def = k
				k = self
			end
			if M._flat[k] ~= nil then
				return M._flat[k]
			elseif def ~= nil then
				return def
			else
				if M.strict_mode then
					error(string.format("no %s found in config", k))
				else
					return
				end
			end
		end
	},{
		__call = function(M, args)
			-- args MUST belong to us, because of modification
			local file
			if type(args) == 'string' then
				file = args
				args = {}
			elseif type(args) == 'table' then
				args = deep_copy(args)
				file = args.file
			else
				args = {}
			end
			if args.bypass_non_dynamic == nil then
				args.bypass_non_dynamic = true
			end
			if args.tidy_load == nil then
				args.tidy_load = true
			end
			M.default_election_mode = args.default_election_mode or 'candidate'
			M.default_synchro_quorum = args.default_synchro_quorum or 'N/2+1'
			M.default_read_only = args.default_read_only or false
			M.master_selection_policy = args.master_selection_policy
			M.default = args.default
			M.strict_mode = args.strict_mode or args.strict or false
			-- print("config", "loading ",file, json.encode(args))
			if not file then
				file = get_opt()
				-- todo: maybe etcd?
				if not file then error("Neither config call option given not -c|--config option passed",2) end
			end

			print(string.format("Loading config %s %s", file, json.encode(args)))

			local function load_config()

				local methods = {}
				function methods.merge(dst, src, keep)
					if src ~= nil then
						deep_merge( dst, src, keep )
					end
					return dst
				end

				function methods.include(path, opts)
					path = fio.pathjoin(fio.dirname(file), path)
					opts = opts or { if_exists = false }
					if not fio.path.exists(path) then
						if opts.if_exists then
							return
						end
						error("Not found include file `"..path.."'", 2)
					end
					local f,e = loadfile(path)
					if not f then error(e,2) end
					setfenv(f, getfenv(2))
					local ret = f()
					if ret ~= nil then
						print("Return value from "..path.." is ignored")
					end
					return
				end

				function methods.print(...)
					local p = {...}
					for i = 1, select('#', ...) do
						if type(p[i]) == 'table'
							and not debug.getmetatable(p[i])
						then
							p[i] = json.encode(p[i])
						end
					end
					print(unpack(p))
				end

				local f,e = loadfile(file)
				if not f then error(e,2) end
				local cfg = setmetatable({}, {
					__index = setmetatable(methods, {
						__index = setmetatable(args,{ __index = _G })
					})
				})
				setfenv(f, cfg)
				local ret = f()
				if ret ~= nil then
					print("Return value from "..file.." is ignored")
				end
				setmetatable(cfg,nil)
				setmetatable(args,nil)
				deep_merge(cfg,args.default or {},'keep')

				-- subject to change, just a PoC
				local etcd_conf = args.etcd or cfg.etcd
				if etcd_conf then
					cfg = etcd_load(M, etcd_conf, cfg)
				end

				if args.load then
					cfg = args.load(M, cfg)
				end

				if not cfg.box then
					error("No box.* config given", 2)
				end

				if args.bypass_non_dynamic then
					cfg.box = prepare_box_cfg(cfg.box)
				end

				deep_merge(cfg,{
					sys = deep_copy(args)
				})
				cfg.sys.boxcfg = nil
				cfg.sys.on_load = nil

				-- if not cfg.box.custom_proc_title and args.instance_name then
				-- 	cfg.box.custom_proc_title = args.instance_name
				-- end

				-- latest modifications and fixups
				if args.on_load then
					args.on_load(M,cfg)
				end
				return cfg
			end

			local cfg = load_config()

			M._flat = flatten(cfg)

			if args.on_before_cfg then
				args.on_before_cfg(M,cfg)
			end

			if args.mkdir then
				if not ( fio.path and fio.mkdir ) then
					error(string.format("Tarantool version %s is too old for mkdir: fio.path is not supported", _TARANTOOL),2)
				end
				for _,key in pairs({"work_dir", "wal_dir", "snap_dir", "memtx_dir", "vinyl_dir"}) do
					local v = cfg.box[key]
					if v and not fio.path.exists(v) then
						local r,e = fio.mktree(v)
						if not r then error(string.format("Failed to create path '%s' for %s: %s",v,key,e),2) end
					end
				end
				local v = cfg.box.pid_file
				if v then
					v = fio.dirname(v);
					if v and not fio.path.exists(v) then
						local r,e = fio.mktree(v)
						if not r then error(string.format("Failed to create path '%s' for pid_file: %s",v,e),2) end
					end
				end
			end

			if cfg.box.remote_addr then
				cfg.box.remote_addr = nil
			end


			-- print(string.format("Starting app: %s", yaml.encode(cfg.box)))
			local boxcfg

			if args.boxcfg then
				args.boxcfg( cfg.box )
			else
				if args.wrap_box_cfg then
					boxcfg = args.wrap_box_cfg
				end
				if type(box.cfg) == 'function' then
					if M.etcd then
						if args.tidy_load then
							local snap_dir = cfg.box.snap_dir or cfg.box.memtx_dir
							if not snap_dir then
								if cfg.box.work_dir then
									snap_dir = cfg.box.work_dir
								else
									snap_dir = "."
								end
							end
							local bootstrapped = false
							for _,v in pairs(fio.glob(snap_dir..'/*.snap')) do
								bootstrapped = v
							end

							if bootstrapped then
								print("Have etcd, use tidy load")
								local ro = cfg.box.read_only
								cfg.box.read_only = true
								log.info("Start tidy loading with ro=true%s (snap=%s)",
									ro ~= true and string.format(' (would be %s)',ro) or '',
									bootstrapped
								)
							else
								log.info("Start non-bootstrapped tidy loading with ro=%s (dir=%s)",cfg.box.read_only, snap_dir)
								if cfg.box.election_mode then
									cfg.box.election_mode = 'off'
								end
							end
						end

						log.info("Just before box.cfg %s", yaml.encode( cfg.box ))

						;(boxcfg or box.cfg)( cfg.box )

						log.info("Reloading config after start")

						local new_cfg = load_config()
						local diff_box = value_diff(cfg.box, new_cfg.box)

						-- since load_config loads config also for reloading it removes non-dynamic options
						-- therefore, they would be absent, but should not be passed. remove them
						if diff_box then
							for key in pairs(diff_box) do
								if peek.dynamic_cfg[key] == nil then
									diff_box[key] = nil
								end
							end
							if not next(diff_box) then
								diff_box = nil
							end
						end

						if diff_box then
							log.info("Reconfigure after load with %s",require'json'.encode(diff_box))
							;(boxcfg or box.cfg)(diff_box)
						else
							log.info("Config is actual after load")
						end

						M._flat = flatten(new_cfg)
					else
						(boxcfg or box.cfg)( cfg.box )
					end
				else
					local replication     = cfg.box.replication_source or cfg.box.replication
					local box_replication = box.cfg.replication_source or box.cfg.replication

					if not is_replication_changed(replication, box_replication) then
						local r  = cfg.box.replication
						local rs = cfg.box.replication_source
						cfg.box.replication        = nil
						cfg.box.replication_source = nil

						(boxcfg or box.cfg)( cfg.box )

						cfg.box.replication        = r
						cfg.box.replication_source = rs
					else
						(boxcfg or box.cfg)( cfg.box )
					end
				end
			end

			if args.on_after_cfg then
				args.on_after_cfg(M,cfg)
			end
			-- print(string.format("Box configured"))

			return M
		end
	})
	rawset(_G,'config',M)

return M
