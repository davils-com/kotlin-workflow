#!/usr/bin/env bash
# Decides whether a tag may be released.
#
#   - The version must not be a snapshot.
#   - The tagged commit has to be on the release branch, so that nobody who can push a tag can
#     release a commit that was never reviewed.
#   - The version has to equal the one the project declares.
#
# A dry run has no tag: it takes the declared version and turns the branch rule into a warning.
#
# Environment: KW_CONFIG (the resolved configuration as JSON), KW_VERSION (from the tag, empty in
#              a dry run), GITHUB_SHA
# Outputs (GITHUB_OUTPUT): version

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_lib/common.sh
source "$here/../_lib/common.sh"

output="${GITHUB_OUTPUT:-/dev/stdout}"

setting() {
  jq --raw-output "$1" <<<"$KW_CONFIG"
}

dry_run="$(setting '.release["dry-run"]')"
branch="$(setting '.release.gate.branch')"
version_file="$(setting '.release.gate["version-file"]')"
version_key="$(setting '.release.gate["version-key"]')"
reject_snapshot="$(setting '.release.gate["reject-snapshot"]')"
working_directory="$(setting '.["working-directory"]')"
version="${KW_VERSION:-}"

fail() {
  echo "::error::$1"
  exit 1
}

declared=""
if [ -n "$version_file" ]; then
  path="$working_directory/$version_file"
  if [ ! -f "$path" ]; then fail "$path does not exist, so the declared version cannot be read."; fi
  declared="$(sed -n "s/^[[:space:]]*${version_key}[[:space:]]*=[[:space:]]*//p" "$path" | head -n 1 | tr -d '\r')"
  if [ -z "$declared" ]; then fail "$path declares no '$version_key'."; fi
fi

if [ -z "$version" ]; then
  if [ "$dry_run" != "true" ]; then fail "No tag was pushed, so there is nothing to release."; fi
  if [ -z "$declared" ]; then fail "A dry run needs release.gate.version-file to know which version to rehearse."; fi
  version="${declared%-SNAPSHOT}"
  echo "Dry run of version $version."
fi

if [ "$reject_snapshot" = "true" ] && [[ "$version" == *-SNAPSHOT ]]; then
  fail "$version is a snapshot. Snapshots are published from the development branch, without a tag."
fi

if [ -n "$declared" ] && [ "${declared%-SNAPSHOT}" != "$version" ]; then
  fail "The release is $version, but $version_file declares $version_key=$declared."
fi

if [ -n "$branch" ]; then
  git fetch --no-tags --quiet origin "$branch:refs/remotes/origin/$branch"
  if ! git merge-base --is-ancestor "$GITHUB_SHA" "refs/remotes/origin/$branch"; then
    message="Commit $GITHUB_SHA is not on $branch."
    if [ "$dry_run" != "true" ]; then fail "$message"; fi
    echo "::warning::$message A real release would stop here."
  fi
fi

echo "version=$version" >>"$output"
