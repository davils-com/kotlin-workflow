#!/usr/bin/env bash
# Names the tests that failed, as error annotations of the job and in its summary, so a failure
# is readable on the page of the run without opening a log or downloading a report.
#
# Environment: KW_CONFIG (the resolved configuration as JSON), KW_WORKING_DIRECTORY,
#              KW_LEG (the name of the matrix leg, for the heading of the summary)

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_lib/common.sh
source "$here/../_lib/common.sh"
summary="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

limit="$(jq --raw-output '.check.summary["failed-tests"]' <<<"$KW_CONFIG")"
if [ "$limit" -le 0 ]; then exit 0; fi

cd "${KW_WORKING_DIRECTORY:-.}"

reports=()
while IFS= read -r report; do
  if [ -n "$report" ]; then reports+=("$report"); fi
done < <("$here/../_lib/find-files.sh" '["**/build/test-results/**/TEST-*.xml"]')
if [ "${#reports[@]}" -eq 0 ]; then exit 0; fi

failed="$(awk '
  function attribute(line, name,    rest, start) {
    start = index(line, " " name "=\"")
    if (start == 0) return ""
    rest = substr(line, start + length(name) + 3)
    return substr(rest, 1, index(rest, "\"") - 1)
  }
  function decoded(text) {
    gsub(/&#13;|&#xD;|\t/, " ", text)
    gsub(/&#10;|&#xA;/, "\001", text)
    gsub(/&quot;/, "\"", text)
    gsub(/&apos;/, "\047", text)
    gsub(/&lt;/, "<", text)
    gsub(/&gt;/, ">", text)
    gsub(/&amp;/, "\\&", text)
    return text
  }
  /<testcase / { test = attribute($0, "name"); suite = attribute($0, "classname") }
  /<(failure|error)[ >]/ {
    if (test == "") next
    print decoded(suite) "\t" decoded(test) "\t" substr(decoded(attribute($0, "message")), 1, 1500)
    test = ""
  }
' "${reports[@]}" | tr -d '\r')"
if [ -z "$failed" ]; then exit 0; fi

total="$(wc -l <<<"$failed" | tr -d ' ')"

escaped() {
  local text="$1"
  text="${text//'%'/%25}"
  text="${text//$'\001'/%0A}"
  printf '%s' "$text"
}

escaped_property() {
  local text
  text="$(escaped "$1")"
  text="${text//:/%3A}"
  text="${text//,/%2C}"
  printf '%s' "$text"
}

{
  echo "### Failed tests${KW_LEG:+ ($KW_LEG)}"
  echo
} >>"$summary"

shown=0
while IFS=$'\t' read -r suite test message; do
  if [ "$shown" -ge "$limit" ]; then break; fi
  shown=$((shown + 1))
  test="${test//$'\001'/ }"
  echo "::error title=$(escaped_property "Failed test: ${suite##*.} > $test")::$(escaped "${message:-The test failed without a message.}")"
  echo "- \`$suite\` > $test" >>"$summary"
done <<<"$failed"

if [ "$total" -gt "$shown" ]; then
  echo "::warning title=More failed tests::$((total - shown)) more tests failed; the report artifact lists them all."
  echo "- and $((total - shown)) more" >>"$summary"
fi
echo >>"$summary"
