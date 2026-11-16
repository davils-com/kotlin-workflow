#!/usr/bin/env bash
# Decides which publications of a release still have to be uploaded.
#
# A release repository refuses to overwrite a file, so a release that failed half way cannot
# simply be run again. Every publication is looked up without credentials and sorted:
#
#   free      nothing of the version exists          -> its task is returned
#   complete  the version is listed in the metadata  -> skipped
#   partial   files exist, the metadata does not     -> the script fails
#
# Gradle writes maven-metadata.xml after every file of a publication, so a listed version is a
# finished upload. A partial one has to be deleted in the repository by hand.
#
# Environment: KW_PUBLICATIONS (JSON [{path, artifact, task}]), KW_REPOSITORY_URL, KW_VERSION
# Outputs (GITHUB_OUTPUT): tasks (JSON list, in the order of the publications)

set -euo pipefail

output="${GITHUB_OUTPUT:-/dev/stdout}"
repository="${KW_REPOSITORY_URL:?KW_REPOSITORY_URL is not set}"
version="${KW_VERSION:?KW_VERSION is not set}"

status_of() {
  curl --silent --show-error --location --output /dev/null --write-out '%{http_code}' --max-time 30 "$1"
}

require_known() {
  case "$1" in
    200 | 404) ;;
    *)
      echo "::error::$2 answered HTTP $1, so the state of the release cannot be decided."
      exit 1
      ;;
  esac
}

is_listed() {
  local metadata
  metadata="$(curl --silent --show-error --location --fail --max-time 30 "$1")"
  grep --quiet --fixed-strings "<version>$version</version>" <<<"$metadata"
}

tasks='[]'
partial=""

while IFS=$'\t' read -r path artifact task; do
  if [ -z "$path" ]; then continue; fi

  metadata_url="$repository/$path/maven-metadata.xml"
  pom_url="$repository/$path/$version/$artifact-$version.pom"

  metadata_status="$(status_of "$metadata_url")"
  require_known "$metadata_status" "$metadata_url"

  if [ "$metadata_status" = "200" ] && is_listed "$metadata_url"; then
    echo "complete  $artifact $version"
    continue
  fi

  pom_status="$(status_of "$pom_url")"
  require_known "$pom_status" "$pom_url"

  if [ "$pom_status" = "200" ]; then
    echo "partial   $artifact $version"
    partial="$partial $path/$version"
    continue
  fi

  echo "free      $artifact $version"
  tasks="$(jq --compact-output --arg task "$task" '. + [$task]' <<<"$tasks")"
done < <(jq --raw-output '.[] | [.path, .artifact, .task] | @tsv' <<<"$KW_PUBLICATIONS")

if [ -n "$partial" ]; then
  echo "::error::A previous upload of $version stopped half way. Delete these directories in the repository, then run the job again:$partial"
  exit 1
fi

echo "tasks=$tasks" >>"$output"
