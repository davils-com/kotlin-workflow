#!/usr/bin/env bash
# Builds a small consumer project against what was just published, the way a user of the library
# would. `{version}` and `{repository}` in the arguments are replaced by the published version and
# the repository URL.
#
# Environment:
#   KW_CONFIG          the resolved configuration as JSON
#   KW_SMOKE           the smoke section of the stage as JSON: {project-dir, tasks, args}
#   KW_VERSION         the published version; empty derives it from the declared version
#   KW_SNAPSHOT        true for a snapshot
#   KW_REPOSITORY_URL  the repository the publication went to
#   KW_MAVEN_USERNAME, KW_MAVEN_PASSWORD   only for a private repository

set -euo pipefail

setting() {
  jq --raw-output "$1" <<<"$KW_CONFIG"
}

fail() {
  echo "::error::$1"
  exit 1
}

project_directory="$(jq --raw-output '.["project-dir"]' <<<"$KW_SMOKE")"
if [ -z "$project_directory" ]; then fail "The smoke build is enabled, but smoke.project-dir is empty."; fi

cd "$(setting '.["working-directory"]')"

version="${KW_VERSION:-}"
if [ -z "$version" ]; then
  version_file="$(setting '.release.gate["version-file"]')"
  version_key="$(setting '.release.gate["version-key"]')"
  if [ -z "$version_file" ]; then fail "The published version is unknown: set release.gate.version-file."; fi
  version="$(sed -n "s/^[[:space:]]*${version_key}[[:space:]]*=[[:space:]]*//p" "$version_file" | head -n 1 | tr -d '\r')"
  if [ -z "$version" ]; then fail "$version_file declares no '$version_key'."; fi
  if [ "${KW_SNAPSHOT:-false}" = "true" ]; then version="${version%-SNAPSHOT}-SNAPSHOT"; fi
fi

if [ -n "${KW_MAVEN_USERNAME:-}" ] && [ -n "${KW_MAVEN_PASSWORD:-}" ]; then
  export "$(setting '.publish["username-env"]')=$KW_MAVEN_USERNAME"
  export "$(setting '.publish["password-env"]')=$KW_MAVEN_PASSWORD"
fi

arguments=()
while IFS= read -r argument; do
  if [ -n "$argument" ]; then arguments+=("$argument"); fi
done < <(jq --raw-output --arg version "$version" --arg repository "${KW_REPOSITORY_URL:-}" \
  '(.tasks + .args)[] | gsub("\\{version\\}"; $version) | gsub("\\{repository\\}"; $repository)' <<<"$KW_SMOKE")

if [ "${#arguments[@]}" -eq 0 ]; then fail "The smoke build is enabled, but smoke.tasks is empty."; fi

echo "./gradlew -p $project_directory ${arguments[*]}"
./gradlew -p "$project_directory" "${arguments[@]}" --no-configuration-cache
