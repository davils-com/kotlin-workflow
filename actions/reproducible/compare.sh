#!/usr/bin/env bash
# Builds the same artifacts twice and fails when their checksums differ.
#
# Environment: KW_CONFIG (the resolved configuration as JSON)

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_lib/common.sh
source "$here/../_lib/common.sh"

cd "$(jq --raw-output '.["working-directory"]' <<<"$KW_CONFIG")"

tasks=()
while IFS= read -r task; do
  if [ -n "$task" ]; then tasks+=("$task"); fi
done < <(jq --raw-output '.check.reproducible.tasks[]' <<<"$KW_CONFIG")

clean_tasks=()
while IFS= read -r task; do
  if [ -n "$task" ]; then clean_tasks+=("$task"); fi
done < <(jq --raw-output '.check.reproducible["clean-tasks"][]' <<<"$KW_CONFIG")

arguments=()
while IFS= read -r argument; do
  if [ -n "$argument" ]; then arguments+=("$argument"); fi
done < <(jq --raw-output '.gradle.args[]' <<<"$KW_CONFIG")

artifacts="$(jq --compact-output '.check.reproducible.artifacts' <<<"$KW_CONFIG")"

checksums() {
  "$here/../_lib/find-files.sh" "$artifacts" | sort | while IFS= read -r file; do
    if command -v sha256sum >/dev/null; then sha256sum "$file"; else shasum -a 256 "$file"; fi
  done
}

build() {
  if [ "${#clean_tasks[@]}" -gt 0 ]; then
    ./gradlew "${clean_tasks[@]}" ${arguments[@]+"${arguments[@]}"} --no-configuration-cache
  fi
  ./gradlew "${tasks[@]}" ${arguments[@]+"${arguments[@]}"} --no-build-cache --no-configuration-cache
  checksums
}

first_sums="$(build | grep -E '^[0-9a-f]{64} ' || true)"
if [ -z "$first_sums" ]; then
  echo "::error::The reproducibility check found no artifact to compare."
  exit 1
fi

"$here/../_lib/find-files.sh" "$artifacts" | while IFS= read -r file; do rm -f "$file"; done

second_sums="$(build | grep -E '^[0-9a-f]{64} ' || true)"

if [ "$first_sums" != "$second_sums" ]; then
  echo "::error::Two builds of the same commit produced different artifacts."
  diff <(echo "$first_sums") <(echo "$second_sums") || true
  exit 1
fi

echo "Both builds produced the same artifacts:"
echo "$second_sums"
