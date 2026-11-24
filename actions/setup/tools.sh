#!/usr/bin/env bash
# Decides which native tools a job installs. Every job takes `tools`; a native runner takes
# `native.tools` as well, which can only add: a tool either of them wants is installed, and the
# packages of both are.
#
# Environment:
#   KW_CONFIG  the resolved configuration as JSON
#   KW_TOOLS   true for `tools`, native for `tools` and `native.tools`
# Outputs (GITHUB_OUTPUT): tools (the tools object as JSON)

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_lib/common.sh
source "$here/../_lib/common.sh"

case "${KW_TOOLS:-true}" in
  true) extra='{}' ;;
  native) extra="$(jq --compact-output '.native.tools // {}' <<<"$KW_CONFIG")" ;;
  *)
    echo "::error::KW_TOOLS is '${KW_TOOLS}', expected true or native."
    exit 1
    ;;
esac

tools="$(jq --compact-output --argjson extra "$extra" '
  reduce ($extra | to_entries[]) as $entry (.tools;
    if ($entry.value | type) == "boolean" then .[$entry.key] = (.[$entry.key] == true or $entry.value)
    elif $entry.key == "packages" then
      .packages as $packages
      | .packages = ($packages + ($entry.value | with_entries(.key as $manager | .value = (($packages[$manager] // []) + .value | unique))))
    else . end)' <<<"$KW_CONFIG")"

echo "tools=$tools" >>"${GITHUB_OUTPUT:-/dev/stdout}"
