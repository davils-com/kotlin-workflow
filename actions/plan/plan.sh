#!/usr/bin/env bash
# Resolves the configuration of one run and decides which stages it starts.
#
# Environment:
#   KW_CONFIG_FILE    path of the project's configuration file; a missing file is no error
#   KW_CONFIG         inline YAML merged over the file
#   KW_STAGES         comma separated stages that replace the policy of the event
#   KW_DRY_RUN        true runs the release stage without uploading
#   KW_CHANGED_FILES  path of a file listing the changed paths, one per line; empty when unknown
#   KW_EVENT_NAME, KW_REF, KW_REF_NAME, KW_CRON, KW_PR_DRAFT   the event that started the run
#
# Outputs (GITHUB_OUTPUT): config, stages, matrix, event, version

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_lib/common.sh
source "$here/../_lib/common.sh"

config_file="${KW_CONFIG_FILE:-.github/kotlin-workflow.yml}"
file_json='{}'
if [ -f "$config_file" ]; then
  file_json="$(yq --output-format=json '. // {}' "$config_file")"
fi

inline_json='{}'
if [ -n "${KW_CONFIG:-}" ]; then
  inline_json="$(yq --output-format=json '. // {}' <<<"$KW_CONFIG")"
fi

changed_json='null'
if [ -n "${KW_CHANGED_FILES:-}" ] && [ -f "$KW_CHANGED_FILES" ]; then
  changed_json="$(jq --raw-input --slurp 'split("\n") | map(select(length > 0))' "$KW_CHANGED_FILES")"
fi

defaults_json="$(yq --output-format=json '.' "$here/defaults.yml")"

plan="$(jq --null-input --compact-output \
  --argjson defaults "$defaults_json" \
  --argjson file "$file_json" \
  --argjson inline "$inline_json" \
  --argjson changed "$changed_json" \
  --arg fileName "$config_file" \
  --arg eventName "${KW_EVENT_NAME:-}" \
  --arg ref "${KW_REF:-}" \
  --arg refName "${KW_REF_NAME:-}" \
  --arg cron "${KW_CRON:-}" \
  --arg draft "${KW_PR_DRAFT:-false}" \
  --arg stagesInput "${KW_STAGES:-}" \
  --arg dryRun "${KW_DRY_RUN:-false}" \
  --from-file "$here/plan.jq")"

if jq --exit-status 'has("errors")' <<<"$plan" >/dev/null; then
  jq --raw-output '.errors[] | "::error::" + .' <<<"$plan"
  exit 1
fi

output="${GITHUB_OUTPUT:-/dev/stdout}"
{
  echo "config=$(jq --compact-output '.config' <<<"$plan")"
  echo "stages=$(jq --compact-output '.stages' <<<"$plan")"
  echo "matrix=$(jq --compact-output '.matrix' <<<"$plan")"
  echo "event=$(jq --raw-output '.event' <<<"$plan")"
  echo "version=$(jq --raw-output '.version' <<<"$plan")"
} >>"$output"

summary="${GITHUB_STEP_SUMMARY:-/dev/null}"
{
  echo "### Plan"
  echo
  echo "| | |"
  echo "|---|---|"
  echo "| Event | \`$(jq --raw-output '.event' <<<"$plan")\` |"
  echo "| Stages | $(jq --raw-output '[.stages | to_entries[] | select(.value) | .key] | if length == 0 then "none" else join(", ") end' <<<"$plan") |"
  echo "| Runners | $(jq --raw-output '[.matrix[].name] | join(", ")' <<<"$plan") |"
  if [ "$(jq '.natives | length' <<<"$plan")" != "0" ]; then
    echo "| Natives | $(jq --raw-output '.natives | join(", ")' <<<"$plan") |"
  fi
  echo "| Gradle cache | $(jq --raw-output '.config.run["cache-mode"]' <<<"$plan") |"
  version="$(jq --raw-output '.version' <<<"$plan")"
  if [ -n "$version" ]; then echo "| Version | \`$version\` |"; fi
  reason="$(jq --raw-output '.reason' <<<"$plan")"
  if [ -n "$reason" ]; then echo "| Skipped because | $reason |"; fi
} >>"$summary"
