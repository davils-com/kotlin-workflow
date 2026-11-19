#!/usr/bin/env bash
# Runs Gradle invocations, one after the other, each from a JSON list of tasks. On Windows its
# twin run.ps1 does the same from PowerShell.
#
# Environment:
#   KW_INVOCATIONS          JSON list of invocations, each a list of tasks and their options
#   KW_ARGS                 JSON list of arguments added to every invocation
#   KW_CONFIGURATION_CACHE  true, false or omit
#   KW_WORKING_DIRECTORY    where the Gradle wrapper is
#   KW_GITHUB_TOKEN         a token the build reads as GITHUB_TOKEN; empty passes none

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_lib/common.sh
source "$here/../_lib/common.sh"

# The build reads the token under the name every tool knows, and only that once: an empty
# GITHUB_TOKEN would read as a token to some tools.
if [ -n "${KW_GITHUB_TOKEN:-}" ]; then export GITHUB_TOKEN="$KW_GITHUB_TOKEN"; fi
unset KW_GITHUB_TOKEN

case "${KW_CONFIGURATION_CACHE:-omit}" in
  true) cache_argument="--configuration-cache" ;;
  false) cache_argument="--no-configuration-cache" ;;
  omit) cache_argument="" ;;
  *)
    echo "::error::KW_CONFIGURATION_CACHE is '${KW_CONFIGURATION_CACHE}', expected true, false or omit."
    exit 1
    ;;
esac

cd "${KW_WORKING_DIRECTORY:-.}"

count="$(jq 'length' <<<"${KW_INVOCATIONS:-[]}")"
index=0

while [ "$index" -lt "$count" ]; do
  arguments=()
  while IFS= read -r argument; do
    if [ -n "$argument" ]; then arguments+=("$argument"); fi
  done < <(jq --raw-output --argjson index "$index" --argjson extra "${KW_ARGS:-[]}" \
    '.[$index] | if length == 0 then empty else (. + $extra)[] end' <<<"$KW_INVOCATIONS")
  index=$((index + 1))

  if [ "${#arguments[@]}" -eq 0 ]; then continue; fi
  if [ -n "$cache_argument" ]; then arguments+=("$cache_argument"); fi

  echo "::group::./gradlew ${arguments[*]}"
  ./gradlew "${arguments[@]}"
  echo "::endgroup::"
done
