#!/usr/bin/env bash
# Installs the native tools a build asks for and fails when one is still missing afterwards: a
# native test that is skipped for a missing tool is not a passing test.
#
# Environment: KW_CONFIG (the resolved configuration as JSON), RUNNER_OS

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_lib/common.sh
source "$here/../_lib/common.sh"

packages_of() {
  jq --raw-output --arg manager "$1" '.tools.packages[$manager][]?' <<<"$KW_CONFIG"
}

wants() {
  [ "$(jq --raw-output --arg tool "$1" '.tools[$tool]' <<<"$KW_CONFIG")" = "true" ]
}

install_all() {
  local manager="$1"
  shift
  local packages=()
  local package
  while IFS= read -r package; do
    if [ -n "$package" ]; then packages+=("$package"); fi
  done < <(packages_of "$manager")
  if [ "${#packages[@]}" -eq 0 ]; then return 0; fi
  "$@" "${packages[@]}"
}

case "${RUNNER_OS:-}" in
  Linux)
    if wants cmake && ! command -v cmake >/dev/null; then
      sudo apt-get update
      sudo apt-get install --yes --no-install-recommends cmake
    fi
    if [ -n "$(packages_of apt)" ]; then
      sudo apt-get update
      install_all apt sudo apt-get install --yes --no-install-recommends
    fi
    ;;
  macOS)
    if wants cmake && ! command -v cmake >/dev/null; then brew install cmake; fi
    install_all brew brew install
    ;;
  Windows)
    if wants cmake && ! command -v cmake >/dev/null; then choco install cmake --yes --no-progress; fi
    install_all choco choco install --yes --no-progress
    ;;
  *)
    echo "::error::The runner operating system '${RUNNER_OS:-}' is not supported."
    exit 1
    ;;
esac

if wants cmake; then cmake --version; fi
if wants cargo; then cargo --version; fi
