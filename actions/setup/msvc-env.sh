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
# The developer environment means the compiler of Visual Studio: CC and CXX become cl, unless the
# job set them already, so that CMake takes cl whatever else is on the PATH. When the job wants
# clang-tidy, the LLVM that Visual Studio ships for the architecture of the runner goes to the end
# of the PATH: its clang-tidy reads the STL of Visual Studio, and its clang and clang++ stay behind
# cl.
#
# Environment:
#   KW_BEFORE, KW_AFTER  the files `set` of cmd.exe wrote
#   KW_CLANG_TIDY        true when the job wants clang-tidy
#   RUNNER_ARCH          X64 or ARM64
#   GITHUB_ENV

set -euo pipefail

before="${KW_BEFORE:?KW_BEFORE is not set}"
after="${KW_AFTER:?KW_AFTER is not set}"
delimiter="kw_$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
changes="$(mktemp)"
entries="$(mktemp)"
trap 'rm -f "$changes" "$entries"' EXIT

if ! awk -v limit=8191 '
  { sub(/\r$/, "") }
  FNR == NR { seen[$0] = 1; next }
  $0 in seen { next }
  index($0, "=") <= 1 { next }
  length($0) >= limit {
    print "::error::" substr($0, 1, index($0, "=") - 1) " is " length($0) " characters long after vcvarsall.bat, more than cmd.exe prints in full."
    failed = 1
    next
  }
  { print > changed }
  END { if (failed) exit 1 }' changed="$changes" "$before" "$after"; then
  exit 1
fi

# value_of <name>: the value of a variable after vcvarsall.bat, whatever the case of its name.
value_of() {
  tr -d '\r' <"$after" | awk -v name="$1" 'index($0, "=") > 1 && tolower(substr($0, 1, index($0, "=") - 1)) == tolower(name) { print substr($0, index($0, "=") + 1); exit }'
}

is_set() {
  tr -d '\r' <"$after" | awk -v name="$1" 'index($0, "=") > 1 && tolower(substr($0, 1, index($0, "=") - 1)) == tolower(name) { found = 1 } END { exit !found }'
}

# The bin directory of the LLVM of Visual Studio, written as the PATH of Windows writes it, when
# the job wants clang-tidy and Visual Studio has one; empty otherwise.
visual_studio_llvm() {
  if [ "${KW_CLANG_TIDY:-false}" != "true" ]; then return 0; fi
  local root separator architecture directory local_directory
  root="$(value_of VCINSTALLDIR)"
  if [ -z "$root" ]; then return 0; fi
  separator='/'
  case "$root" in *\\*) separator="\\" ;; esac
  case "${RUNNER_ARCH:-X64}" in
    ARM64) architecture=ARM64 ;;
    *) architecture=x64 ;;
  esac
  root="${root%[\\/]}"
  directory="$root${separator}Tools${separator}Llvm${separator}$architecture${separator}bin"
  local_directory="$directory"
  if command -v cygpath >/dev/null; then local_directory="$(cygpath --unix "$directory")"; fi
  if [ -x "$local_directory/clang-tidy.exe" ] || [ -x "$local_directory/clang-tidy" ]; then echo "$directory"; fi
}

entry() {
  {
    echo "$1<<$delimiter"
    echo "$2"
    echo "$delimiter"
  } >>"$entries"
}

llvm="$(visual_studio_llvm)"
path_written=false
count=0

while IFS= read -r line; do
  name="${line%%=*}"
  value="${line#*=}"
  if [ -n "$llvm" ] && [ "$(tr '[:upper:]' '[:lower:]' <<<"$name")" = "path" ]; then
    value="$value;$llvm"
    path_written=true
  fi
  entry "$name" "$value"
  count=$((count + 1))
done <"$changes"

if [ -n "$llvm" ] && [ "$path_written" = "false" ]; then
  entry Path "$(value_of Path);$llvm"
  count=$((count + 1))
fi

for compiler in CC CXX; do
  if is_set "$compiler"; then continue; fi
  entry "$compiler" cl
  count=$((count + 1))
done

cat "$entries" >>"$GITHUB_ENV"
echo "$count variable(s) set."
if [ -n "$llvm" ]; then echo "clang-tidy of Visual Studio, behind cl: $llvm"; fi
