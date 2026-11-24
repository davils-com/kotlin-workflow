#!/usr/bin/env bash
# Uploads publications. The repository token, and the signing key of a release, exist in this one
# step only, under the names the build reads them from. Every task is its own Gradle invocation,
# in order, and the configuration cache stays off so that no secret is written to it.
#
# Environment:
#   KW_CONFIG           the resolved configuration as JSON
#   KW_TASKS            JSON list of upload tasks
#   KW_ARGS             JSON list of arguments of every upload; empty takes gradle.args
#   KW_SNAPSHOT         true publishes a snapshot
#   KW_MAVEN_USERNAME, KW_MAVEN_PASSWORD
#   KW_SIGNING_KEY, KW_SIGNING_KEY_ID, KW_SIGNING_PASSWORD   only for a signed release

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_lib/common.sh
source "$here/../_lib/common.sh"

setting() {
  jq --raw-output "$1" <<<"$KW_CONFIG"
}

fail() {
  echo "::error::$1"
  exit 1
}

username_env="$(setting '.publish["username-env"]')"
password_env="$(setting '.publish["password-env"]')"

for name in "$username_env" "$password_env"; do
  if ! [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then fail "'$name' is not a valid name for an environment variable."; fi
done

if [ -z "${KW_MAVEN_USERNAME:-}" ] || [ -z "${KW_MAVEN_PASSWORD:-}" ]; then
  fail "The repository token is empty. Pass the secrets MAVEN_USERNAME and MAVEN_PASSWORD, or define them in the environment of this job."
fi

export "$username_env=$KW_MAVEN_USERNAME"
export "$password_env=$KW_MAVEN_PASSWORD"

if [ "${KW_SNAPSHOT:-false}" = "true" ]; then
  if [ "$(setting '.snapshot["kreate-snapshot"]')" = "true" ]; then export KREATE_SNAPSHOT=true; fi
elif [ "$(setting '.release.sign')" = "true" ]; then
  if [ -z "${KW_SIGNING_KEY:-}" ]; then fail "The signing key is empty. Pass the secret SIGNING_KEY, define it in the environment of this job, or set release.sign to false."; fi
  export ORG_GRADLE_PROJECT_signingInMemoryKey="$KW_SIGNING_KEY"
  export ORG_GRADLE_PROJECT_signingInMemoryKeyId="${KW_SIGNING_KEY_ID:-}"
  export ORG_GRADLE_PROJECT_signingInMemoryKeyPassword="${KW_SIGNING_PASSWORD:-}"
fi

arguments=()
while IFS= read -r argument; do
  if [ -n "$argument" ]; then arguments+=("$argument"); fi
done < <(if [ -n "${KW_ARGS:-}" ]; then jq --raw-output '.[]' <<<"$KW_ARGS"; else jq --raw-output '.gradle.args[]' <<<"$KW_CONFIG"; fi)

cd "$(setting '.["working-directory"]')"

count=0
while IFS= read -r task; do
  if [ -z "$task" ]; then continue; fi
  echo "./gradlew $task"
  ./gradlew "$task" ${arguments[@]+"${arguments[@]}"} --no-configuration-cache
  count=$((count + 1))
done < <(jq --raw-output '.[]' <<<"$KW_TASKS")

if [ "$count" -eq 0 ]; then echo "Nothing left to upload."; fi
