# Docker common things
#
# INPUT VARIABLES
# 	- QUAY_USER: The quay.io user to use (usually set in CI)
# 	- QUAY_PASSWD: The quay passwd to use  (usually set in CI)
# 	- IMAGE: the docker image to use. will be computed if it doesn't exist.
# 	- REGISTRY: The docker registry to use. defaults to quay.
#
# EXPORT VARIABLES
# 	- BUILD_NUM: The build number for this build. Will use pants default sandbox
# 	             if not on circleCI, if that isn't available will defauilt to 'dev'.
# 	             If it is in circle will use CIRCLE_BUILD_NUM otherwise.
# 	- IMAGE: The image to use for the build.
# 	- REGISTRY: The registry to use for the build.
#
#-------------------------------------------------------------------------------
# use pants if it exists outside of circle to get the default namespace and use it for the build
ifndef CIRCLECI
   BUILD_NUM := $(shell pants sandbox | grep Default | awk '{print $$NF}' 2> /dev/null)
endif
ifndef BUILD_NUM
   BUILD_NUM := dev
endif

ifdef CIRCLE_BUILD_NUM
  BUILD_NUM := $(CIRCLE_BUILD_NUM)
  QUAY := docker login -p "$$QUAY_PASSWD" -u "$$QUAY_USER" -e "unused@unused" quay.io
endif

# These can be overridden
IMAGE ?= $(REGISTRY)/$(APP):$(BUILD_NUM)
REGISTRY ?= quay.io/getpantheon

# if there is a docker file then set the docker variable so things can trigger off it
ifneq ("$(wildcard Dockerfile))","")
  # file is there
  DOCKER:=true
endif

# determine the docker tag to build
build-docker::
ifndef  DOCKER
	$(error "Docker task called, but no DOCKER variable set. Either Dockerfile is missing or you didn't include common.")
endif
build-docker:: build-linux setup-quay ## build the docker container
	docker build -t $(IMAGE) .

# stub build-linux std target
build-linux::

push:: ## push the container to the registry
	docker push $(IMAGE)

setup-quay:: ## setup docker login for quay.io
ifdef CIRCLE_BUILD_NUM
ifndef QUAY_PASSWD
	$(error "Need to set QUAY_PASSWD environment variable")
endif
ifndef QUAY_USER
	$(error "Need to set QUAY_USER environment variable")
endif
endif
	@$(QUAY)

# we call make here to ensure new states are detected
push-circle:: ## build and push the container from circle
	make build-docker
push-circle:: setup-quay
	make push

.PHONY:: setup-quay build-docker push push-circle
