etcd = {
	instance_name = os.getenv("TT_INSTANCE_NAME"),
	prefix = '/instance',
	endpoints = {"http://etcd0:2379","http://etcd1:2379","http://etcd2:2379"},
	fencing_enabled = true,
	timeout = 2,
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
