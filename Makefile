APP := kube-gce-cleanup

SHELL_SOURCES=lib/* delete-orphaned-kube-network-load-balancers.sh

include devops/make/common.mk
include devops/make/common-shell.mk
include devops/make/common-docs.mk
include devops/make/common-docker.mk

build-docker::
ifeq ($(CIRCLE_BRANCH), master)
	@echo "Tagging latest master"
	docker tag -f $(IMAGE) quay.io/getpantheon/$(APP):latest
endif

push::
ifeq ($(CIRCLE_BRANCH), master)
	@echo "Pushing latest tag"
	docker push quay.io/getpantheon/$(APP):latest
endif


test::
	docker run -v $(PWD):/app:z techangels/bats:0.4.0	/app/tests/valid_target_pool.sh

test-circle::
	docker run -v $(PWD):/app:z techangels/bats:0.4.0	/app/tests/valid_target_pool.sh
