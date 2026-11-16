#!/usr/bin/env bash
# Commits a patch of regenerated lock files and checksums to the branch of a pull request.
#
# The patch was written by a job that ran the project's build, so it is not trusted: it may touch
# nothing but the paths the configuration allows, and it may only change or add plain files. This
# script runs no code of the project.
#
# Environment:
#   KW_CONFIG        the resolved configuration as JSON
#   KW_PATCH         the patch to apply
#   KW_EXPECTED_SHA  the commit the patch was made for
#   KW_BRANCH        the branch of the pull request
#   KW_PUSH_URL      where to push; the caller builds it with its token
# Outputs (GITHUB_OUTPUT): pushed

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
output="${GITHUB_OUTPUT:-/dev/stdout}"

fail() {
  echo "::error::$1"
  exit 1
}

if [ ! -s "$KW_PATCH" ]; then
  echo "pushed=false" >>"$output"
  echo "Nothing to commit."
  exit 0
fi

head="$(git rev-parse HEAD)"
if [ "$head" != "$KW_EXPECTED_SHA" ]; then
  echo "pushed=false" >>"$output"
  echo "::notice::The branch moved from $KW_EXPECTED_SHA to $head while the records were regenerated. The run of the newer commit takes over."
  exit 0
fi

allowed="$(jq --compact-output '.dependencies.paths' <<<"$KW_CONFIG")"

paths="$(git apply --numstat "$KW_PATCH" | cut -f 3-)"
if [ -z "$paths" ]; then fail "The patch names no file."; fi

refused="$(jq --raw-input --raw-output --argjson globs "$allowed" -L "$here/../_lib" \
  'include "glob"; . as $path | select(any($globs[]; glob_regex as $re | $path | test($re)) | not)' <<<"$paths")"
if [ -n "$refused" ]; then
  fail "The patch touches files it may not change: $(tr '\n' ' ' <<<"$refused")"
fi

summary="$(git apply --summary "$KW_PATCH")"
if grep --quiet --extended-regexp '^ (rename|copy|delete mode|mode change)' <<<"$summary"; then
  fail "The patch renames, deletes or changes the mode of a file."
fi
if grep --extended-regexp '^ create mode' <<<"$summary" | grep --quiet --invert-match ' create mode 100644 '; then
  fail "The patch creates something other than a plain file."
fi

git apply --index "$KW_PATCH"

message="$(jq --raw-output '.dependencies["commit-message"]' <<<"$KW_CONFIG")"
git -c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
  commit --quiet --message "$message"

git push --quiet "$KW_PUSH_URL" "HEAD:refs/heads/$KW_BRANCH"

echo "pushed=true" >>"$output"
echo "Committed $(git rev-parse --short HEAD) to $KW_BRANCH:"
echo "$paths"
