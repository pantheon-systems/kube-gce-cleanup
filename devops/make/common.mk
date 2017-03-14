# common make tasks and variables that should be imported into all projects
#
#-------------------------------------------------------------------------------
help: ## print list of tasks and descriptions
	@grep --no-filename -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?##"}; { printf "\033[36m%-30s\033[0m %s \n", $$1, $$2}'
.DEFAULT_GOAL := help

## empty global tasks are defined here, makefiles can attach tasks to them

deps:: ## install build and test dependencies
deps-circle:: ## install build and test dependencies on circle-ci
lint:: ## run all linters
test:: ## run all tests
test-circle:: ## invoke test tasks for CI
test-coverage:: ## run test coverage reports
build:: ## run all build

update-makefiles: ## update the make subtree, assumes the subtree is in devops/make
	@if [ -e scripts/make ] ; then \
		echo "Directory scripts/make exists. You should convert to using the devops dir" ; \
		echo "git rm -r scripts/make" ;\
		echo "git commit -m \"Remove common_makefiles from old prefix\"" ;\
		echo "git subtree add --prefix devops/make common_makefiles master --squash" ; \
		echo "sed -i 's/scripts\/make/devops\/make/g' Makefile" ; \
		echo "git commit -am \"Move common_makefiles to new prefix\"" ; \
		exit 1 ; \
	fi
	git subtree pull --prefix devops/make common_makefiles master --squash

.PHONY:: all help update-makefiles
