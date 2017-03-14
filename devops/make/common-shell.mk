# See README.md for docs: https://github.com/pantheon-systems/common_makefiles

## Append tasks to the global tasks
test:: test-shell
test-circle:: test-shell
deps-circle:: deps-circle-shell

# version of shellcheck to install from deps-circle
export SHELLCHECK_VERSION := 0.4.5

ifndef SHELL_SOURCES
	SHELL_SOURCES := $(shell find . -name \*.sh)
endif

test-shell:: ## run shellcheck tests
ifdef SHELL_SOURCES
	shellcheck $(SHELL_SOURCES)
endif

deps-circle-shell::
ifdef SHELL_SOURCES
	@bash devops/make/sh/install-shellcheck.sh
endif

# TODO: add some patterns for integration tests with bats. example: https://github.com/joemiller/creds
