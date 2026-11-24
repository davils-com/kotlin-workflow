#!/usr/bin/env bash
# Hands every variable vcvarsall.bat set or changed to the later steps of the job. msvc.ps1 wrote
# the environment of cmd.exe before and after vcvarsall.bat, as `set` prints it, and only what
# differs between the two is handed on: a variable vcvarsall.bat left alone is never written,
# whatever cmd.exe made of it.
#
# cmd.exe prints no variable of 8191 characters or more in full: it cuts it off and runs the next
# variable into it. msvc.ps1 keeps such variables away from cmd.exe; a changed line that long is
# one vcvarsall.bat made, it cannot be trusted, and it stops the job.
#
# Environment: KW_BEFORE, KW_AFTER (the files `set` of cmd.exe wrote), GITHUB_ENV

set -euo pipefail

before="${KW_BEFORE:?KW_BEFORE is not set}"
after="${KW_AFTER:?KW_AFTER is not set}"
delimiter="kw_$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
changes="$(mktemp)"
trap 'rm -f "$changes"' EXIT

if ! awk -v limit=8191 -v delimiter="$delimiter" '
  { sub(/\r$/, "") }
  FNR == NR { seen[$0] = 1; next }
  $0 in seen { next }
  index($0, "=") <= 1 { next }
  length($0) >= limit {
    print "::error::" substr($0, 1, index($0, "=") - 1) " is " length($0) " characters long after vcvarsall.bat, more than cmd.exe prints in full."
    failed = 1
    next
  }
  {
    name = substr($0, 1, index($0, "=") - 1)
    print name "<<" delimiter > changed
    print substr($0, index($0, "=") + 1) > changed
    print delimiter > changed
    count++
  }
  END {
    if (failed) exit 1
    print count + 0 " variable(s) set."
  }' changed="$changes" "$before" "$after"; then
  exit 1
fi

cat "$changes" >>"$GITHUB_ENV"
