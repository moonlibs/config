etcd = {
	instance_name = os.getenv("TT_INSTANCE_NAME"),
	prefix = '/instance',
	endpoints = {"http://etcd:2379"},
	fencing_enabled = true,
}

box = {
	background = false,
	log_level = 6,
	log_format = 'plain',

	memtx_dir = '/var/lib/tarantool/snaps/',
	wal_dir = '/var/lib/tarantool/xlogs',
}

app = {

}