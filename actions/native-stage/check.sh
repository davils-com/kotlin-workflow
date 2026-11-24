#!/usr/bin/env bash
# Checks the stage a native runner built before it is kept: the stage task left a stage, and every
# library of it was built for the platform native.runners declares for this runner. A runner whose
# label leads to another machine than declared, an x86_64 one for windows-aarch64 say, stops here
# and not in the publishing build.
#
# The stage holds <artifact>/<platform>/ with the libraries and a native.properties, as Kreate's
# kreateJniStage writes it.
#
# Environment: KW_CONFIG (the resolved configuration as JSON), KW_PLATFORM
# Outputs (GITHUB_OUTPUT): directory (the stage, as a path the upload understands)

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_lib/common.sh
source "$here/../_lib/common.sh"

platform="${KW_PLATFORM:?KW_PLATFORM is not set}"
directory="$(jq --raw-output '.["working-directory"]' <<<"$KW_CONFIG")/$(jq --raw-output '.native["stage-directory"]' <<<"$KW_CONFIG")"
task="$(jq --raw-output '.native["stage-task"]' <<<"$KW_CONFIG")"

fail() {
  echo "::error::$1"
  exit 1
}

if [ ! -d "$directory" ]; then fail "$task left no stage in $directory."; fi

found=0
for staged in "$directory"/*/*/; do
  if [ ! -d "$staged" ]; then continue; fi
  staged="${staged%/}"
  name="$(basename "$staged")"
  artifact="$(basename "$(dirname "$staged")")"
  if [ "$name" != "$platform" ]; then
    fail "$task staged $artifact for $name on a runner that native.runners declares as $platform."
  fi
  if [ ! -f "$staged/native.properties" ]; then fail "$staged has no native.properties."; fi
  if ! tr -d '\r' <"$staged/native.properties" | grep --quiet --line-regexp --fixed-strings "platform=$platform"; then
    fail "The native.properties of $staged names another platform than $platform."
  fi
  echo "staged  $artifact  $platform"
  found=$((found + 1))
done

if [ "$found" -eq 0 ]; then fail "$task staged nothing in $directory."; fi

echo "directory=$directory" >>"${GITHUB_OUTPUT:-/dev/stdout}"
