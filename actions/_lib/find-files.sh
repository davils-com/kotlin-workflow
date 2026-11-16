#!/usr/bin/env bash
# Prints the files below the current directory that match one of the globs in a JSON list, one per
# line. Build outputs are searched, version control and Gradle's own state are not.
#
# Usage: find-files.sh '<json list of globs>'

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$here/common.sh"
globs="${1:-[]}"

find . \( -name .git -o -name .gradle -o -name node_modules \) -prune -o -type f -print \
  | sed 's|^\./||' \
  | jq --raw-input --raw-output --argjson globs "$globs" -L "$here" \
      'include "glob"; . as $path | select(any($globs[]; glob_regex as $re | $path | test($re)))'
