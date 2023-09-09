
run-compose-etcd:
	docker compose up -d --remove-orphans --build etcd0 etcd1 etcd2

run-compose: run-compose-etcd
	docker compose up -d --remove-orphans --build
