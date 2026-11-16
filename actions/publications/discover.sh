#!/usr/bin/env bash
# Lists the publications of a build as JSON: [{path, artifact, task}].
#
# `explicit` takes the list from the configuration. `auto` asks Gradle through an init script,
# which reaches every project of the build but not the included builds of a composite.
#
# Environment: KW_CONFIG (the resolved configuration as JSON)
# Outputs (GITHUB_OUTPUT): publications

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_lib/common.sh
source "$here/../_lib/common.sh"
output="${GITHUB_OUTPUT:-/dev/stdout}"

discovery="$(jq --raw-output '.release.publications.discovery' <<<"$KW_CONFIG")"

case "$discovery" in
  explicit)
    publications="$(jq --compact-output '.release.publications.list' <<<"$KW_CONFIG")"
    invalid="$(jq '[.[] | select((.path | type) != "string" or (.artifact | type) != "string" or (.task | type) != "string")] | length' <<<"$publications")"
    if [ "$invalid" != "0" ]; then
      echo "::error::Every entry of release.publications.list needs a path, an artifact and a task."
      exit 1
    fi
    ;;
  auto)
    repository="$(jq --raw-output '.publish.repository.name' <<<"$KW_CONFIG")"
    cd "$(jq --raw-output '.["working-directory"]' <<<"$KW_CONFIG")"
    lines="$(./gradlew kotlinWorkflowPublications --init-script "$here/list-publications.init.gradle.kts" \
      "-PkotlinWorkflow.repository=$repository" --no-configuration-cache --quiet | grep '^KW|' || true)"
    publications="$(jq --raw-input --slurp --compact-output \
      'split("\n") | map(select(length > 0) | split("|") | {path: .[1], artifact: .[2], task: .[4]})' <<<"$lines")"
    ;;
  *)
    echo "::error::release.publications.discovery is '$discovery', expected auto or explicit."
    exit 1
    ;;
esac

if [ "$(jq 'length' <<<"$publications")" = "0" ]; then
  echo "::error::The build has no publication to release."
  exit 1
fi

echo "publications=$publications" >>"$output"
jq --raw-output '.[] | "publication  \(.path)  \(.task)"' <<<"$publications"
