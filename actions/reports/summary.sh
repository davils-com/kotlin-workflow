#!/usr/bin/env bash
# Writes what a check produced to the job summary: test totals from the JUnit reports, line
# coverage from the Kover report and the assurance report of Kreate.
#
# Environment: KW_CONFIG (the resolved configuration as JSON), KW_WORKING_DIRECTORY

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
summary="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

cd "${KW_WORKING_DIRECTORY:-.}"

enabled() {
  [ "$(jq --raw-output --arg key "$1" '.check.summary[$key]' <<<"$KW_CONFIG")" = "true" ]
}

attribute_sum() {
  local attribute="$1"
  shift
  grep --no-filename --only-matching "<testsuite [^>]*" "$@" \
    | sed -n "s/.* $attribute=\"\([0-9]*\)\".*/\1/p" \
    | awk '{ total += $1 } END { print total + 0 }'
}

tests_summary() {
  local reports=()
  local report
  while IFS= read -r report; do
    if [ -n "$report" ]; then reports+=("$report"); fi
  done < <("$here/../_lib/find-files.sh" '["**/build/test-results/**/TEST-*.xml"]')
  if [ "${#reports[@]}" -eq 0 ]; then return 0; fi

  local tests failures errors skipped
  tests="$(attribute_sum tests "${reports[@]}")"
  failures="$(attribute_sum failures "${reports[@]}")"
  errors="$(attribute_sum errors "${reports[@]}")"
  skipped="$(attribute_sum skipped "${reports[@]}")"
  {
    echo "### Tests"
    echo
    echo "| Tests | Failed | Errors | Skipped |"
    echo "|---|---|---|---|"
    echo "| $tests | $failures | $errors | $skipped |"
    echo
  } >>"$summary"
}

coverage_summary() {
  local report rows=""
  while IFS= read -r report; do
    if [ -z "$report" ]; then continue; fi
    local counter missed covered
    counter="$(grep --only-matching '<counter type="LINE" missed="[0-9]*" covered="[0-9]*"/>' "$report" | tail -n 1 || true)"
    if [ -z "$counter" ]; then continue; fi
    missed="$(sed -n 's/.*missed="\([0-9]*\)".*/\1/p' <<<"$counter")"
    covered="$(sed -n 's/.*covered="\([0-9]*\)".*/\1/p' <<<"$counter")"
    rows="$rows| \`${report%/build/reports/kover/report.xml}\` | $(awk -v c="$covered" -v m="$missed" 'BEGIN { if (c + m == 0) print "n/a"; else printf "%.1f %%", 100 * c / (c + m) }') |"$'\n'
  done < <("$here/../_lib/find-files.sh" '["**/build/reports/kover/report.xml"]')
  if [ -z "$rows" ]; then return 0; fi
  {
    echo "### Line coverage"
    echo
    echo "| Project | Covered |"
    echo "|---|---|"
    printf '%s' "$rows"
    echo
  } >>"$summary"
}

assurance_summary() {
  local report
  while IFS= read -r report; do
    if [ -z "$report" ]; then continue; fi
    {
      echo "### Assurance"
      echo
      cat "$report"
      echo
    } >>"$summary"
  done < <("$here/../_lib/find-files.sh" '["**/build/kreate/assurance/reports/report.md"]')
}

if enabled tests; then tests_summary; fi
if enabled coverage; then coverage_summary; fi
if enabled assurance; then assurance_summary; fi
