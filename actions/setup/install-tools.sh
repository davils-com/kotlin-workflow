#!/usr/bin/env bash
# Installs the native tools a build asks for and fails when one is still missing afterwards: a
# native test that is skipped for a missing tool is not a passing test.
#
# A tool that is on the PATH already is taken as it is. The developer environment of Visual Studio
# is set up by msvc.ps1 in the step before, which puts the CMake and the Ninja of Visual Studio on
# the PATH as well, and the clang-tidy of Visual Studio at its end; this script only checks that
# its compiler is there and that the clang-tidy found is that of Visual Studio.
#
# Environment:
#   KW_TOOLS      the tools object as JSON, as tools.sh chose it
#   RUNNER_OS     Linux, macOS or Windows
#   RUNNER_ARCH   X64 or ARM64
#   VCINSTALLDIR  set by the developer environment of Visual Studio
#   GITHUB_PATH   where a directory added to the PATH is handed to the later steps

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_lib/common.sh
source "$here/../_lib/common.sh"

packages_of() {
  jq --raw-output --arg manager "$1" '.packages[$manager][]?' <<<"$KW_TOOLS"
}

wants() {
  [ "$(jq --raw-output --arg tool "$1" '.[$tool]' <<<"$KW_TOOLS")" = "true" ]
}

missing() {
  wants "$1" && ! command -v "$1" >/dev/null
}

# add_path <directory>: for this step and every later one of the job.
add_path() {
  local directory="$1"
  export PATH="$directory:$PATH"
  if [ "${RUNNER_OS:-}" = "Windows" ] && command -v cygpath >/dev/null; then directory="$(cygpath --windows "$directory")"; fi
  echo "$directory" >>"${GITHUB_PATH:-/dev/null}"
}

# The bin directory of the LLVM that Visual Studio ships for the architecture of the runner, when
# msvc.ps1 set up Visual Studio and it has one; empty otherwise.
visual_studio_llvm() {
  local root="${VCINSTALLDIR:-}" architecture
  if [ -z "$root" ]; then return 0; fi
  if command -v cygpath >/dev/null; then root="$(cygpath --unix "$root")"; fi
  case "${RUNNER_ARCH:-X64}" in
    ARM64) architecture=ARM64 ;;
    *) architecture=x64 ;;
  esac
  local directory="${root%/}/Tools/Llvm/$architecture/bin"
  if [ -x "$directory/clang-tidy.exe" ] || [ -x "$directory/clang-tidy" ]; then echo "$directory"; fi
}

# install <command...>: runs the command with the packages collected in `wanted`, if there are any.
wanted=()
install() {
  local package
  while IFS= read -r package; do
    if [ -n "$package" ]; then wanted+=("$package"); fi
  done < <(packages_of "$manager")
  if [ "${#wanted[@]}" -eq 0 ]; then return 0; fi
  "$@" "${wanted[@]}"
}

case "${RUNNER_OS:-}" in
  Linux)
    manager=apt
    if missing cmake; then wanted+=(cmake); fi
    if missing ninja; then wanted+=(ninja-build); fi
    if missing clang-tidy; then wanted+=(clang-tidy); fi
    if [ "${#wanted[@]}" -gt 0 ] || [ -n "$(packages_of apt)" ]; then sudo apt-get update; fi
    install sudo apt-get install --yes --no-install-recommends
    ;;
  macOS)
    manager=brew
    if missing cmake; then wanted+=(cmake); fi
    if missing ninja; then wanted+=(ninja); fi
    # Homebrew keeps LLVM off the PATH, so that its clang does not shadow the one of Xcode.
    if missing clang-tidy; then wanted+=(llvm); fi
    install brew install
    if missing clang-tidy; then add_path "$(brew --prefix llvm)/bin"; fi
    ;;
  Windows)
    manager=choco
    if missing cmake; then wanted+=(cmake); fi
    if missing ninja; then wanted+=(ninja); fi
    # Next to Visual Studio, msvc-env.sh put the LLVM of Visual Studio at the end of the PATH; see
    # the check of the clang-tidy that was found below.
    llvm="/c/Program Files/LLVM/bin"
    if missing clang-tidy && [ ! -x "$llvm/clang-tidy.exe" ]; then wanted+=(llvm); fi
    install choco install --yes --no-progress
    if missing clang-tidy; then add_path "$llvm"; fi
    ;;
  *)
    echo "::error::The runner operating system '${RUNNER_OS:-}' is not supported."
    exit 1
    ;;
esac

if wants cmake; then cmake --version; fi
if wants ninja; then printf "ninja "; ninja --version; fi
if wants clang-tidy; then clang-tidy --version; fi
# clang-tidy reads the headers of the STL of Visual Studio, which refuses a Clang older than the
# one Visual Studio ships. Next to Visual Studio, the clang-tidy found has to be that one.
visual_studio_llvm="$(visual_studio_llvm)"
if wants clang-tidy && [ -n "$visual_studio_llvm" ]; then
  found="$(command -v clang-tidy)"
  case "$found" in
    "$visual_studio_llvm"/*) ;;
    *)
      echo "::error::The clang-tidy on the PATH is $found, not the one of Visual Studio in $visual_studio_llvm. It would refuse the STL of Visual Studio."
      exit 1
      ;;
  esac
fi
if wants cargo; then cargo --version; fi
if wants msvc && [ "${RUNNER_OS:-}" = "Windows" ]; then
  if ! command -v cl.exe >/dev/null; then
    echo "::error::The compiler of Visual Studio, cl.exe, is not on the PATH."
    exit 1
  fi
  echo "cl $(command -v cl.exe)"
fi
