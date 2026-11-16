#!/usr/bin/env bash
# Checks how the workflows and actions of this repository reference other code.
#
#   - A reference into this repository uses the self reference `$/`.
#   - Every other action is pinned to a full commit SHA and names its version in a comment on the
#     same line, which is what Dependabot keeps current.
#   - One action is pinned to one commit everywhere.

set -euo pipefail

cd "${KW_ROOT:-$(dirname "${BASH_SOURCE[0]}")/..}"

status=0
references="$(grep -rnE '^[[:space:]]*(-[[:space:]]+)?uses:' .github/workflows actions || true)"

while IFS= read -r line; do
  if [ -z "$line" ]; then continue; fi
  location="${line%%:[[:space:]]*}"
  reference="$(sed -E 's/^.*uses:[[:space:]]*//' <<<"$line")"
  target="${reference%%[[:space:]]*}"

  case "$target" in
    \$/*) continue ;;
    ./*)
      echo "$location: '$target' is relative to the caller's checkout. Use \$/ for this repository."
      status=1
      continue
      ;;
  esac

  if ! [[ "$target" =~ @[0-9a-f]{40}$ ]]; then
    echo "$location: '$target' is not pinned to a full commit SHA."
    status=1
  fi
  if ! [[ "$reference" =~ \#[[:space:]]*v[0-9] ]]; then
    echo "$location: '$target' names no version in a comment."
    status=1
  fi
done <<<"$references"

pins="$(sed -E 's/^.*uses:[[:space:]]*//; s/[[:space:]].*$//' <<<"$references" | grep '@' | sort -u || true)"
duplicates="$(awk -F'@' '{ split($1, parts, "/"); print parts[1] "/" parts[2] " " $2 }' <<<"$pins" | sort -u | awk '{ print $1 }' | uniq -d || true)"

if [ -n "$duplicates" ]; then
  echo "Pinned to more than one commit: $(tr '\n' ' ' <<<"$duplicates")"
  status=1
fi

if [ "$status" -eq 0 ]; then echo "Every reference is pinned."; fi
exit "$status"
