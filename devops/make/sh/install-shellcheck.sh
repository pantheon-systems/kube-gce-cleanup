#!/bin/bash
# install dependencies on circle-ci
#
# This script requires two things from your circle.yml:
# - ~/.cabal should be a cached directory.
# - $HOME/.cabal/bin should be in the $PATH
#
# Example circle.yml:
#
#   machine:
#     environment:
#       PATH: $PATH:$HOME/.cabal/bin/
#
#   dependencies:
#     cache_directories:
#       - ~/.cabal
#

set -ex

# we need to find the root of the git repo. NOTE: this will be either empty string '' or something like '../'. Beware of the empty string
repo_root=$(git rev-parse --show-cdup)

# shellcheck disable=SC2088
if ! grep -q '~/.cabal' "${repo_root}circle.yml"; then
  echo 'ERROR: "~/.cabal" not found in circle.yml!!! This will add over 5 minutes to every build! fix this!!!!!'
  exit 1
fi

if [[ ! "$PATH" =~ .cabal/bin ]]; then
    # shellcheck disable=SC2016
    echo 'ERROR: PATH env variable is missing "$HOME/.cabal/bin"'
    exit 1
fi

# install shellcheck (https://github.com/koalaman/shellcheck)
SHELLCHECK_VERSION="${SHELLCHECK_VERSION-0.4.5}"
echo "$SHELLCHECK_VERSION"
SHELLCHECK_BIN="$HOME/.cabal/bin/shellcheck"

existing_version=$("$SHELLCHECK_BIN" -V | awk '/version:/ {print $2}')
if [[ "$existing_version" != "$SHELLCHECK_VERSION" ]]; then
  rm -f -- "$SHELLCHECK_BIN"
  echo "Installing ShellCheck $SHELLCHECK_VERSION"
  cabal update --verbose=0
  cabal install --verbose=0 "shellcheck-$SHELLCHECK_VERSION"
else
  echo "Shellcheck $SHELLCHECK_VERSION already installed."
fi
