#!/usr/bin/env bash
# Regenerates the lock files and the verification metadata of a build after its versions changed,
# and writes what changed as a patch. Only the paths the configuration allows end up in the patch,
# whatever else the build touched.
#
# This script runs the build, so it runs without any permission to write and without a secret.
# The patch is applied by another job that runs no code of the project.
#
# Environment: KW_CONFIG (the resolved configuration as JSON), KW_PATCH (where to write the patch)
# Outputs (GITHUB_OUTPUT): changed

set -euo pipefail

output="${GITHUB_OUTPUT:-/dev/stdout}"
root="$(pwd)"

setting() {
  jq --raw-output "$1" <<<"$KW_CONFIG"
}

arguments=()
while IFS= read -r argument; do
  if [ -n "$argument" ]; then arguments+=("$argument"); fi
done < <(jq --raw-output '.gradle.args[]' <<<"$KW_CONFIG")

cd "$(setting '.["working-directory"]')"

count="$(jq '.dependencies.lock.invocations | length' <<<"$KW_CONFIG")"
index=0
while [ "$index" -lt "$count" ]; do
  invocation=()
  while IFS= read -r item; do
    if [ -n "$item" ]; then invocation+=("$item"); fi
  done < <(jq --raw-output --argjson index "$index" '.dependencies.lock.invocations[$index][]' <<<"$KW_CONFIG")
  index=$((index + 1))
  if [ "${#invocation[@]}" -eq 0 ]; then continue; fi
  echo "::group::./gradlew ${invocation[*]}"
  ./gradlew "${invocation[@]}" ${arguments[@]+"${arguments[@]}"} --no-configuration-cache
  echo "::endgroup::"
done

verification_file="$(setting '.dependencies.verification.file')"
if [ "$(setting '.dependencies.verification.enabled')" = "true" ] && [ -f "$verification_file" ]; then
  tasks=()
  while IFS= read -r task; do
    if [ -n "$task" ]; then tasks+=("$task"); fi
  done < <(jq --raw-output '.dependencies.verification.tasks[]' <<<"$KW_CONFIG")
  checksums="$(setting '.dependencies.verification.checksums')"
  echo "::group::./gradlew --write-verification-metadata $checksums ${tasks[*]}"
  # Gradle writes the metadata of everything it resolved even when a task fails afterwards. Whether
  # the build is sound is decided by the check that runs on the repaired commit, not here.
  if ! ./gradlew --write-verification-metadata "$checksums" "${tasks[@]}" ${arguments[@]+"${arguments[@]}"} --no-configuration-cache; then
    echo "::warning::The build failed while its checksums were recorded. The check of the new commit shows why."
  fi
  echo "::endgroup::"
fi

cd "$root"

pathspecs=()
while IFS= read -r path; do
  if [ -n "$path" ]; then pathspecs+=(":(glob)$path"); fi
done < <(jq --raw-output '.dependencies.paths[]' <<<"$KW_CONFIG")

if [ "${#pathspecs[@]}" -eq 0 ]; then
  echo "::error::dependencies.paths is empty, so nothing could ever be committed."
  exit 1
fi

git ls-files --others --exclude-standard -- "${pathspecs[@]}" | while IFS= read -r file; do
  if [ -n "$file" ]; then git add --intent-to-add -- "$file"; fi
done
git diff --binary --no-color -- "${pathspecs[@]}" >"$KW_PATCH"

if [ -s "$KW_PATCH" ]; then
  echo "changed=true" >>"$output"
  git diff --stat -- "${pathspecs[@]}"
else
  echo "changed=false" >>"$output"
  echo "The lock files and the checksums are current."
fi
