#!/usr/bin/env bash
# Appends the Markdown files that match a glob to the job summary.
#
# Environment: KW_GLOB, KW_TITLE, KW_WORKING_DIRECTORY

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
summary="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

if [ -z "${KW_GLOB:-}" ]; then exit 0; fi

cd "${KW_WORKING_DIRECTORY:-.}"

"$here/../_lib/find-files.sh" "$(jq --null-input --compact-output --arg glob "$KW_GLOB" '[$glob]')" | sort | while IFS= read -r file; do
  if [ -z "$file" ]; then continue; fi
  {
    echo "### ${KW_TITLE:-Report}: \`$file\`"
    echo
    cat "$file"
    echo
  } >>"$summary"
done
