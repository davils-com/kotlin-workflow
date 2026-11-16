#!/usr/bin/env bash
# Exports the `env` map of the configuration to every later step of the job.
#
# Environment: KW_CONFIG (the resolved configuration as JSON)

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_lib/common.sh
source "$here/../_lib/common.sh"

names="$(jq --raw-output '.env // {} | keys[]' <<<"$KW_CONFIG")"

while IFS= read -r name; do
  if [ -z "$name" ]; then continue; fi
  if ! [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    echo "::error::'$name' is not a valid name for an environment variable."
    exit 1
  fi
  value="$(jq --raw-output --arg name "$name" '.env[$name] | tostring' <<<"$KW_CONFIG")"
  delimiter="kw_$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
  {
    echo "$name<<$delimiter"
    echo "$value"
    echo "$delimiter"
  } >>"$GITHUB_ENV"
done <<<"$names"
