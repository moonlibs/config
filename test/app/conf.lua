etcd = {
	instance_name = os.getenv("TT_INSTANCE_NAME"),
	prefix = '/instance',
	endpoints = {"http://etcd0:2379","http://etcd1:2379","http://etcd2:2379"},
	fencing_enabled = false,
	timeout = 2,
	login = 'username',
	password = 'password',
}
