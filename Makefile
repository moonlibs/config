.PHONY := all test

run-compose:
	make -C test run-compose

build-testing-image:
	docker build -t config-test -f Dockerfile.test .

test: build-testing-image run-compose
	docker run --name config-test \
		--net tt_net \
		-e TT_ETCD_ENDPOINTS="http://etcd0:2379,http://etcd1:2379,http://etcd2:2379" \
		--rm -v $$(pwd):/source/config \
		--workdir /source/config \
		--entrypoint '' \
		config-test \
		./run_test_in_docker.sh
