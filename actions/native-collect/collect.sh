#!/usr/bin/env bash
# Checks the merged stages of the native runners and builds the arguments that hand them to the
# publishing build. Every artifact of the stage has to carry every platform of native.runners and
# nothing else: a platform that is missing would be published without its library, one that is
# not declared would be published by nobody's decision. What is inside each platform, the
# manifest, the checksums and the commit, the build checks itself.
#
# Environment: KW_CONFIG (the resolved configuration as JSON), KW_DIRECTORY (the merged stages)
# Outputs (GITHUB_OUTPUT):
#   args               JSON list: gradle.args, -P<stage-property>=<directory> and
#                      -P<platforms-property>=<platform,...>, each property only when it is named
#   build-invocations  JSON list of one invocation: publish.build-tasks, then native.build-tasks

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_lib/common.sh
source "$here/../_lib/common.sh"

directory="${KW_DIRECTORY:?KW_DIRECTORY is not set}"
output="${GITHUB_OUTPUT:-/dev/stdout}"

fail() {
  echo "::error::$1"
  exit 1
}

platforms="$(jq --raw-output '.native.runners[].platform' <<<"$KW_CONFIG")"
if [ -z "$platforms" ]; then fail "native.runners is empty, so there is no stage to collect."; fi
if [ ! -d "$directory" ]; then fail "No native runner left a stage in $directory."; fi

artifacts=0
for artifact in "$directory"/*/; do
  if [ ! -d "$artifact" ]; then continue; fi
  artifact="${artifact%/}"
  name="$(basename "$artifact")"
  artifacts=$((artifacts + 1))

  for staged in "$artifact"/*/; do
    if [ ! -d "$staged" ]; then continue; fi
    platform="$(basename "${staged%/}")"
    if ! grep --quiet --line-regexp --fixed-strings "$platform" <<<"$platforms"; then
      fail "The stage of $name holds $platform, which native.runners does not list."
    fi
  done

  while IFS= read -r platform; do
    if [ ! -d "$artifact/$platform" ]; then fail "The stage of $name has no $platform."; fi
    echo "collected  $name  $platform"
  done <<<"$platforms"
done

if [ "$artifacts" -eq 0 ]; then fail "No native runner left a stage in $directory."; fi

args="$(jq --compact-output --arg directory "$directory" '
  .native as $native
  | .gradle.args
    + (if ($native["stage-property"] | length) > 0 then ["-P\($native["stage-property"])=\($directory)"] else [] end)
    + (if ($native["platforms-property"] | length) > 0
       then ["-P\($native["platforms-property"])=\([$native.runners[].platform] | join(","))"] else [] end)' <<<"$KW_CONFIG")"

build_invocations="$(jq --compact-output '
  .publish["build-tasks"] as $build | [$build + (.native["build-tasks"] - $build)]' <<<"$KW_CONFIG")"

{
  echo "args=$args"
  echo "build-invocations=$build_invocations"
} >>"$output"
