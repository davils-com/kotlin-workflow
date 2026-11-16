#!/usr/bin/env bash
# Lists the paths an event changed, one per line, so that the plan can skip runs that touch
# nothing but ignored files. An event without a comparison, or a failed lookup, leaves the list
# unknown, and an unknown list never skips anything.
#
# Environment: GH_TOKEN, GITHUB_REPOSITORY, KW_EVENT_NAME, KW_PR_NUMBER, KW_BEFORE, KW_AFTER,
#              KW_MERGE_BASE, KW_MERGE_HEAD
# Outputs (GITHUB_OUTPUT): file (empty when the list is unknown)

set -euo pipefail

readonly no_commit="0000000000000000000000000000000000000000"
readonly compare_limit=300

target="${RUNNER_TEMP:-/tmp}/kotlin-workflow-changed-files"
output="${GITHUB_OUTPUT:-/dev/stdout}"

unknown() {
  echo "file=" >>"$output"
  exit 0
}

compare() {
  local base="$1" head="$2"
  if [ -z "$base" ] || [ -z "$head" ] || [ "$base" = "$no_commit" ]; then unknown; fi
  if ! gh api "repos/$GITHUB_REPOSITORY/compare/$base...$head" --jq '.files[].filename' >"$target"; then
    echo "::warning::The changed files could not be listed, so nothing is skipped."
    unknown
  fi
  if [ "$(wc -l <"$target")" -ge "$compare_limit" ]; then unknown; fi
}

case "${KW_EVENT_NAME:-}" in
  pull_request)
    if ! gh api "repos/$GITHUB_REPOSITORY/pulls/$KW_PR_NUMBER/files" --paginate --jq '.[].filename' >"$target"; then
      echo "::warning::The changed files could not be listed, so nothing is skipped."
      unknown
    fi
    ;;
  push) compare "${KW_BEFORE:-}" "${KW_AFTER:-}" ;;
  merge_group) compare "${KW_MERGE_BASE:-}" "${KW_MERGE_HEAD:-}" ;;
  *) unknown ;;
esac

echo "file=$target" >>"$output"
