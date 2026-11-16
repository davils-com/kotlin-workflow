#!/usr/bin/env bash
# Fails when the runner carries local development state of Kreate. A build that resolves a local
# snapshot there would verify something nobody else can resolve.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_lib/common.sh
source "$here/../_lib/common.sh"

gradle_home="${GRADLE_USER_HOME:-$HOME/.gradle}"

if [ -d "$gradle_home/kreate/local" ]; then
  echo "::error::$gradle_home/kreate/local exists: this runner holds local Kreate publications. Clear them with kreateLocalClean before building here."
  exit 1
fi
