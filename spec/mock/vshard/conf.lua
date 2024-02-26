local tt_etcd_endpoints = assert(os.getenv('TT_ETCD_ENDPOINTS'))
local endpoints = tt_etcd_endpoints:gsub(',+', ','):gsub(',$',''):split(',')

etcd = {
	instance_name = instance_name,
	endpoints = endpoints,
	prefix = os.getenv('TT_ETCD_PREFIX'),
}

box = {
	wal_dir = os.getenv('TT_WAL_DIR') ..'/' .. instance_name,
	memtx_dir = os.getenv('TT_MEMTX_DIR') .. '/' .. instance_name,
	log = os.getenv('TT_MEMTX_DIR') .. '/' .. instance_name .. '.log',
}
