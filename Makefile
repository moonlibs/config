.PHONY := all test

run-etcd:
	make -C test run-compose-etcd

config-test-builder:
	docker build -t moonlibs-config-test-builder:latest -f Dockerfile.build .

config-test-%: config-test-builder run-etcd
	docker build -t $(@) --build-arg IMAGE=$(subst config-test-,,$@) -f Dockerfile.test .

test-%: config-test-%
	docker run --rm --name $(<) \
		--net tt_net \
		-e TT_ETCD_ENDPOINTS="http://etcd0:2379,http://etcd1:2379,http://etcd2:2379" \
		-v $$(pwd):/source/config \
		-v $$(pwd)/data:/tmp/ \
		--workdir /source/config \
		--entrypoint '' \
		$(<) \
		./run_test_in_docker.sh
