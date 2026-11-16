#!/usr/bin/env bash
# Collects the SARIF files that match a glob into one file ready for code scanning.
#
# Environment: KW_GLOB (a glob; empty switches the collection off), KW_CATEGORY, KW_WORKING_DIRECTORY
# Outputs (GITHUB_OUTPUT): file (empty when nothing matched)

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_lib/common.sh
source "$here/../_lib/common.sh"
output="${GITHUB_OUTPUT:-/dev/stdout}"
target="${RUNNER_TEMP:-/tmp}/kotlin-workflow-${KW_CATEGORY:-sarif}.sarif"

if [ -z "${KW_GLOB:-}" ]; then
  echo "file=" >>"$output"
  exit 0
fi

cd "${KW_WORKING_DIRECTORY:-.}"

files=()
while IFS= read -r file; do
  if [ -n "$file" ]; then files+=("$file"); fi
done < <("$here/../_lib/find-files.sh" "$(jq --null-input --compact-output --arg glob "$KW_GLOB" '[$glob]')")

if [ "${#files[@]}" -eq 0 ]; then
  echo "No SARIF file matches '$KW_GLOB'."
  echo "file=" >>"$output"
  exit 0
fi

jq --slurp --from-file "$here/merge.jq" "${files[@]}" >"$target"
echo "Merged ${#files[@]} SARIF file(s) into $target."
echo "file=$target" >>"$output"
