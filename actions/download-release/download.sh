#!/usr/bin/env bash
# Downloads a published release the way a consumer would, without credentials, and checks that
# every file a build needs is there. The JARs stay in KW_DIRECTORY so that their provenance can be
# verified afterwards.
#
# A publication whose POM says <packaging>pom</packaging>, such as a plugin marker or a BOM, has
# nothing but its POM. Every other one has a JAR, and a module file when Gradle published one.
#
# Environment: KW_PUBLICATIONS (JSON [{path, artifact, task}]), KW_REPOSITORY_URL, KW_VERSION,
#              KW_SIGNED (true expects an .asc next to every file), KW_DIRECTORY

set -euo pipefail

repository="${KW_REPOSITORY_URL:?KW_REPOSITORY_URL is not set}"
version="${KW_VERSION:?KW_VERSION is not set}"
directory="${KW_DIRECTORY:?KW_DIRECTORY is not set}"
signed="${KW_SIGNED:-true}"

mkdir -p "$directory"

fetch() {
  local url="$1" target
  target="$directory/$(basename "$url")"
  if ! curl --silent --show-error --location --fail --max-time 120 --output "$target" "$url"; then
    echo "::error::$url is missing from the release."
    exit 1
  fi
  if [ ! -s "$target" ]; then
    echo "::error::$url is empty."
    exit 1
  fi
  echo "found  $url"
}

fetch_with_signature() {
  fetch "$1"
  if [ "$signed" = "true" ]; then fetch "$1.asc"; fi
}

exists() {
  [ "$(curl --silent --show-error --location --output /dev/null --write-out '%{http_code}' --max-time 30 "$1")" = "200" ]
}

while IFS=$'\t' read -r path artifact; do
  if [ -z "$path" ]; then continue; fi
  base="$repository/$path/$version/$artifact-$version"

  fetch_with_signature "$base.pom"
  if grep --quiet '<packaging>pom</packaging>' "$directory/$artifact-$version.pom"; then continue; fi

  fetch_with_signature "$base.jar"
  if exists "$base.module"; then fetch_with_signature "$base.module"; fi
done < <(jq --raw-output '.[] | [.path, .artifact] | @tsv' <<<"$KW_PUBLICATIONS")
