#!/usr/bin/env bash
# Lints the workflows, the composite actions and their scripts.
#
# actionlint does not know the self reference `$/` yet, so it reads a temporary copy in which it
# is written as `./`. Both spellings resolve to this repository, which is all a linter needs to
# follow a reference. zizmor knows `$/` and reads the files as they are.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
copy="$(mktemp -d)"
trap 'rm -rf "$copy"' EXIT

cd "$root"

# None of the linters reads a script from standard input; without this some of them wait for it.
exec </dev/null

for tool in actionlint zizmor shellcheck; do
  if ! command -v "$tool" >/dev/null; then
    echo "$tool is not installed." >&2
    exit 1
  fi
done

git ls-files --cached --others --exclude-standard -z | while IFS= read -r -d '' file; do
  if [ ! -f "$file" ]; then continue; fi
  mkdir -p "$copy/$(dirname "$file")"
  cp "$file" "$copy/$file"
done

# shellcheck disable=SC2016
find "$copy" -name '*.yml' -print0 | xargs -0 perl -pi -e 's{(uses:\s*)\$/}{$1./}'

git init --quiet "$copy"

echo "actionlint"
(cd "$copy" && actionlint -color)

echo "zizmor"
zizmor --min-severity low --no-progress .github/workflows actions

echo "shellcheck"
git ls-files --cached --others --exclude-standard '*.sh' | while IFS= read -r file; do
  if [ -f "$file" ]; then echo "$file"; fi
done | xargs shellcheck

echo "All clean."
