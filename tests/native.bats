#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load helpers

setup() {
  setup_workspace
  unset KW_CONFIG KW_STAGES KW_DRY_RUN KW_CHANGED_FILES KW_CRON KW_PR_DRAFT KW_ARGS KW_TOOLS
  export KW_CONFIG_FILE="$workspace/kotlin-workflow.yml"
  export GITHUB_PATH="$workspace/path"
  : >"$GITHUB_PATH"
}

teardown() {
  teardown_workspace
}

plan() {
  run "$repository_root/actions/plan/plan.sh"
}

push_to() {
  export KW_EVENT_NAME=push KW_REF="refs/heads/$1" KW_REF_NAME="$1"
}

config() {
  output_value config | jq --raw-output "$1"
}

# A resolved configuration of the native fixture, as the plan job hands it on.
native_config() {
  cp "$repository_root/fixtures/config/native.yml" "$KW_CONFIG_FILE"
  push_to develop
  "$repository_root/actions/plan/plan.sh" >/dev/null
  output_value config
  : >"$GITHUB_OUTPUT"
}

# stage <directory> <artifact> <platform> [manifest platform]
stage() {
  mkdir -p "$1/$2/$3"
  echo "library" >"$1/$2/$3/$2.dll"
  printf 'format=1\nplatform=%s\ngroup=com.example\nartifact=%s\nversion=1.0.0\n' "${4:-$3}" "$2" >"$1/$2/$3/native.properties"
}

# --- plan -------------------------------------------------------------------------------------

@test "a project without natives plans as before" {
  cp "$repository_root/fixtures/config/plain.yml" "$KW_CONFIG_FILE"
  push_to develop
  plan
  [ "$status" -eq 0 ]
  [ "$(config '.run["native-stages"] | length')" = "0" ]
  [ "$(output_value stages | jq --raw-output 'has("native")')" = "false" ]
  [ "$(output_value stages | jq --raw-output '.snapshot')" = "true" ]
  ! grep -q "Natives" "$GITHUB_STEP_SUMMARY"
}

@test "the defaults build no natives" {
  push_to develop
  plan
  [ "$status" -eq 0 ]
  [ "$(config '.native.runners | length')" = "0" ]
  [ "$(config '.run["native-stages"] | length')" = "0" ]
}

@test "a project with natives publishes them with snapshots and releases" {
  cp "$repository_root/fixtures/config/native.yml" "$KW_CONFIG_FILE"
  push_to develop
  plan
  [ "$status" -eq 0 ]
  [ "$(config '.run["native-stages"] | join(",")')" = "snapshot,release" ]
  [ "$(config '[.native.runners[].platform] | join(",")')" = "windows-x86_64,windows-aarch64" ]
  [ "$(config '.native.runners[1]["runs-on"]')" = "windows-11-arm" ]
  [ "$(config '.native.runners[1].jdk.distribution')" = "microsoft" ]
  [ "$(config '.native.runners[0] | has("jdk")')" = "false" ]
  grep -q "| Natives | windows-x86_64, windows-aarch64 |" "$GITHUB_STEP_SUMMARY"
}

@test "a run that publishes nothing names no natives" {
  cp "$repository_root/fixtures/config/native.yml" "$KW_CONFIG_FILE"
  push_to feature/pipes
  plan
  [ "$status" -eq 0 ]
  ! grep -q "Natives" "$GITHUB_STEP_SUMMARY"
}

@test "natives can be built by the check as well" {
  cp "$repository_root/fixtures/config/native.yml" "$KW_CONFIG_FILE"
  export KW_CONFIG='native: { stages: [check, release] }'
  export KW_EVENT_NAME=pull_request KW_REF=refs/pull/7/merge KW_REF_NAME=7/merge
  plan
  [ "$status" -eq 0 ]
  [ "$(config '.run["native-stages"] | join(",")')" = "check,release" ]
  grep -q "| Natives | windows-x86_64, windows-aarch64 |" "$GITHUB_STEP_SUMMARY"
}

@test "a runner may name a list of labels" {
  push_to develop
  export KW_CONFIG='native: { runners: [{ platform: linux-aarch64, runs-on: [self-hosted, arm64] }] }'
  plan
  [ "$status" -eq 0 ]
  [ "$(config '.native.runners[0]["runs-on"] | join(",")')" = "self-hosted,arm64" ]
}

@test "an unknown platform stops the plan" {
  push_to develop
  export KW_CONFIG='native: { runners: [{ platform: windows-arm64, runs-on: windows-11-arm }] }'
  plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"native.runners[0].platform: 'windows-arm64' is not one of linux-x86_64"* ]]
}

@test "every problem of the runners is reported at once" {
  push_to develop
  export KW_CONFIG='native: { stage-task: "", stages: [docs], runners: [{ platform: linux-x86_64, runs-on: ubuntu-latest, os: linux }, { platform: linux-x86_64 }, windows-latest] }'
  plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"native.runners[0].os: unknown option"* ]]
  [[ "$output" == *"native.runners[1].runs-on: expected a runner label or a list of labels"* ]]
  [[ "$output" == *"native.runners[2]: expected an object, got string"* ]]
  [[ "$output" == *"native.runners: the platform linux-x86_64 is listed twice"* ]]
  [[ "$output" == *"native.stages: 'docs' is not one of check, snapshot, release"* ]]
  [[ "$output" == *"native.stage-task: empty, but native.runners lists runners"* ]]
}

@test "a runner may set the JDK of its own" {
  push_to develop
  export KW_CONFIG='native: { runners: [{ platform: windows-aarch64, runs-on: windows-11-arm, jdk: { distribution: microsoft, version: 25 } }] }'
  plan
  [ "$status" -eq 0 ]
  [ "$(config '.native.runners[0].jdk.distribution')" = "microsoft" ]
  [ "$(config '.jdk.distribution')" = "temurin" ]
}

@test "the JDK of a runner is validated" {
  push_to develop
  export KW_CONFIG='native: { runners: [{ platform: windows-aarch64, runs-on: windows-11-arm, jdk: { vendor: microsoft, distribution: [microsoft] } }, { platform: windows-x86_64, runs-on: windows-latest, jdk: microsoft }] }'
  plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"native.runners[0].jdk.vendor: unknown option"* ]]
  [[ "$output" == *"native.runners[0].jdk.distribution: expected string, got array"* ]]
  [[ "$output" == *"native.runners[1].jdk: expected an object, got string"* ]]
}

@test "native options are validated like the rest" {
  push_to develop
  export KW_CONFIG='native: { stage-taks: kreateJniStage, runners: {} }'
  plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"native.stage-taks: unknown option"* ]]
  [[ "$output" == *"native.runners: expected array, got object"* ]]
}

# --- tools ------------------------------------------------------------------------------------

@test "a job takes the tools of the configuration" {
  KW_CONFIG="$(native_config)" KW_TOOLS=true run "$repository_root/actions/setup/tools.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value tools | jq --raw-output '.msvc')" = "false" ]
  [ "$(output_value tools | jq --raw-output '.ninja')" = "false" ]
}

@test "a native runner adds the tools of native.tools" {
  config="$(native_config | jq --compact-output '.tools.cargo = true | .tools.packages.apt = ["gcc"] | .native.tools.packages.apt = ["gcc", "g++"]')"
  KW_CONFIG="$config" KW_TOOLS=native run "$repository_root/actions/setup/tools.sh"
  [ "$status" -eq 0 ]
  tools="$(output_value tools)"
  [ "$(jq --raw-output '[.msvc, .cmake, .ninja, .["clang-tidy"], .cargo] | map(tostring) | join(",")' <<<"$tools")" = "true,true,true,true,true" ]
  [ "$(jq --raw-output '.packages.apt | join(",")' <<<"$tools")" = "g++,gcc" ]
  [ "$(jq --raw-output '.trivy' <<<"$tools")" = "" ]
}

@test "another choice of tools is refused" {
  KW_CONFIG="$(default_config)" KW_TOOLS=all run "$repository_root/actions/setup/tools.sh"
  [ "$status" -eq 1 ]
}

# A PATH with nothing but what the script needs, and stand-ins for the package managers.
isolated_path() {
  mkdir -p "$workspace/system" "$workspace/fake"
  local tool
  for tool in bash env jq tr dirname chmod mkdir; do ln -s "$(command -v "$tool")" "$workspace/system/$tool"; done
  cat >"$workspace/fake/sudo" <<'SCRIPT'
#!/usr/bin/env bash
"$@"
SCRIPT
  cat >"$workspace/fake/apt-get" <<'SCRIPT'
#!/usr/bin/env bash
echo "apt-get $*" >>"$(dirname "$0")/installed"
if [ "$1" = install ]; then
  for package in "$@"; do
    case "$package" in
      ninja-build) printf '#!/usr/bin/env bash\necho 1.12.1\n' >"$(dirname "$0")/ninja" ;;
      clang-tidy | cmake) printf '#!/usr/bin/env bash\necho %s version 1\n' "$package" >"$(dirname "$0")/$package" ;;
      *) continue ;;
    esac
    chmod +x "$(dirname "$0")/${package%-build}"
  done
fi
SCRIPT
  cat >"$workspace/fake/brew" <<'SCRIPT'
#!/usr/bin/env bash
here="$(dirname "$0")"
case "$1" in
  install) echo "brew $*" >>"$here/installed"; mkdir -p "$here/llvm/bin"; printf '#!/usr/bin/env bash\necho LLVM\n' >"$here/llvm/bin/clang-tidy"; chmod +x "$here/llvm/bin/clang-tidy" ;;
  --prefix) echo "$here/llvm" ;;
esac
SCRIPT
  chmod +x "$workspace/fake/sudo" "$workspace/fake/apt-get" "$workspace/fake/brew"
  isolated="$workspace/fake:$workspace/system"
}

@test "Linux installs every missing tool in one go" {
  isolated_path
  run env PATH="$isolated" RUNNER_OS=Linux KW_TOOLS='{"cmake":false,"ninja":true,"clang-tidy":true,"msvc":true,"cargo":false,"packages":{"apt":["libssl-dev"]}}' \
    "$repository_root/actions/setup/install-tools.sh"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'apt-get update' "$workspace/fake/installed")" = "1" ]
  grep -q 'apt-get install --yes --no-install-recommends ninja-build clang-tidy libssl-dev' "$workspace/fake/installed"
  [[ "$output" == *"ninja 1.12.1"* ]]
}

@test "Linux installs nothing when nothing is asked for" {
  isolated_path
  run env PATH="$isolated" RUNNER_OS=Linux KW_TOOLS="$(default_config | jq --compact-output '.tools')" \
    "$repository_root/actions/setup/install-tools.sh"
  [ "$status" -eq 0 ]
  [ ! -e "$workspace/fake/installed" ]
}

@test "macOS puts the clang-tidy of Homebrew's LLVM on the PATH of later steps" {
  isolated_path
  run env PATH="$isolated" RUNNER_OS=macOS KW_TOOLS='{"cmake":false,"ninja":false,"clang-tidy":true,"msvc":false,"cargo":false,"packages":{"brew":[]}}' \
    "$repository_root/actions/setup/install-tools.sh"
  [ "$status" -eq 0 ]
  grep -q 'brew install llvm' "$workspace/fake/installed"
  [ "$(cat "$GITHUB_PATH")" = "$workspace/fake/llvm/bin" ]
  [[ "$output" == *"LLVM"* ]]
}

# A Visual Studio with its LLVM for both architectures, and a clang-tidy of LLVM 20 elsewhere.
visual_studio() {
  isolated_path
  printf '#!/usr/bin/env bash\n' >"$workspace/fake/cl.exe"
  printf '#!/usr/bin/env bash\necho LLVM version 20\n' >"$workspace/fake/clang-tidy"
  chmod +x "$workspace/fake/cl.exe" "$workspace/fake/clang-tidy"
  local architecture
  for architecture in x64 ARM64; do
    mkdir -p "$workspace/vs/VC/Tools/Llvm/$architecture/bin"
    printf '#!/usr/bin/env bash\necho LLVM version 22 of Visual Studio %s\n' "$architecture" >"$workspace/vs/VC/Tools/Llvm/$architecture/bin/clang-tidy"
    chmod +x "$workspace/vs/VC/Tools/Llvm/$architecture/bin/clang-tidy"
  done
  msvc_tools='{"cmake":false,"ninja":false,"clang-tidy":true,"msvc":true,"cargo":false,"packages":{}}'
}

@test "next to Visual Studio, the clang-tidy of Visual Studio at the end of the PATH is taken" {
  visual_studio
  rm "$workspace/fake/clang-tidy"
  run env PATH="$isolated:$workspace/vs/VC/Tools/Llvm/ARM64/bin" RUNNER_OS=Windows RUNNER_ARCH=ARM64 \
    VCINSTALLDIR="$workspace/vs/VC/" KW_TOOLS="$msvc_tools" "$repository_root/actions/setup/install-tools.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"of Visual Studio ARM64"* ]]
  [ ! -s "$GITHUB_PATH" ]
}

@test "next to Visual Studio, another clang-tidy ahead of it fails the job" {
  visual_studio
  run env PATH="$isolated:$workspace/vs/VC/Tools/Llvm/x64/bin" RUNNER_OS=Windows RUNNER_ARCH=X64 \
    VCINSTALLDIR="$workspace/vs/VC/" KW_TOOLS="$msvc_tools" "$repository_root/actions/setup/install-tools.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::The clang-tidy on the PATH is $workspace/fake/clang-tidy, not the one of Visual Studio"* ]]
}

@test "without Visual Studio, any clang-tidy on the PATH is taken" {
  visual_studio
  run env PATH="$isolated" RUNNER_OS=Windows RUNNER_ARCH=X64 KW_TOOLS="$msvc_tools" \
    "$repository_root/actions/setup/install-tools.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"LLVM version 20"* ]]
  [ ! -s "$GITHUB_PATH" ]
}

@test "the developer environment puts the LLVM of Visual Studio behind cl, ahead of any other LLVM, and names cl the compiler" {
  visual_studio
  dump "$workspace/before" 'Path=C:\tools\bin;C:\Program Files\LLVM\bin;C:\Windows'
  dump "$workspace/after" 'Path=C:\VS\bin\HostX64\x64;C:\VS\IDE;C:\tools\bin;C:\Program Files\LLVM\bin;C:\Windows' \
    "VCINSTALLDIR=$workspace/vs/VC/"
  : >"$workspace/env"
  KW_BEFORE="$workspace/before" KW_AFTER="$workspace/after" KW_CLANG_TIDY=true RUNNER_ARCH=X64 GITHUB_ENV="$workspace/env" \
    run "$repository_root/actions/setup/msvc-env.sh"
  [ "$status" -eq 0 ]
  expected="C:\\VS\\bin\\HostX64\\x64;C:\\VS\\IDE;$workspace/vs/VC/Tools/Llvm/x64/bin;C:\\tools\\bin;C:\\Program Files\\LLVM\\bin;C:\\Windows"
  [ "$(sed -n '/^Path<</{n;p;}' "$workspace/env")" = "$expected" ]
  [ "$(sed -n '/^CC<</{n;p;}' "$workspace/env")" = "cl" ]
  [ "$(sed -n '/^CXX<</{n;p;}' "$workspace/env")" = "cl" ]
}

@test "without clang-tidy the PATH of the developer environment stays as vcvarsall.bat made it" {
  visual_studio
  dump "$workspace/before" 'Path=C:\Windows'
  dump "$workspace/after" 'Path=C:\VS\bin;C:\Windows' "VCINSTALLDIR=$workspace/vs/VC/"
  : >"$workspace/env"
  KW_BEFORE="$workspace/before" KW_AFTER="$workspace/after" KW_CLANG_TIDY=false GITHUB_ENV="$workspace/env" \
    run "$repository_root/actions/setup/msvc-env.sh"
  [ "$status" -eq 0 ]
  grep -qx 'C:\\VS\\bin;C:\\Windows' "$workspace/env"
  ! grep -q 'Llvm' "$workspace/env"
}

@test "a compiler the job named itself stays" {
  dump "$workspace/before" 'CC=clang-cl' 'Path=C:\Windows'
  dump "$workspace/after" 'CC=clang-cl' 'Path=C:\VS\bin;C:\Windows'
  : >"$workspace/env"
  KW_BEFORE="$workspace/before" KW_AFTER="$workspace/after" GITHUB_ENV="$workspace/env" \
    run "$repository_root/actions/setup/msvc-env.sh"
  [ "$status" -eq 0 ]
  ! grep -q '^CC<<' "$workspace/env"
  [ "$(sed -n '/^CXX<</{n;p;}' "$workspace/env")" = "cl" ]
}

@test "a tool that is still missing fails the job" {
  isolated_path
  rm "$workspace/fake/apt-get"
  printf '#!/usr/bin/env bash\n' >"$workspace/fake/apt-get"
  chmod +x "$workspace/fake/apt-get"
  run -127 env PATH="$isolated" RUNNER_OS=Linux KW_TOOLS='{"cmake":false,"ninja":true,"clang-tidy":false,"msvc":false,"cargo":false,"packages":{}}' \
    "$repository_root/actions/setup/install-tools.sh"
  [ ! -e "$workspace/fake/ninja" ]
}

# What `set` of cmd.exe prints, with the line ends of Windows: dump <file> <line...>
dump() {
  local file="$1"
  shift
  printf '%s\r\n' "$@" >"$file"
}

@test "the variables vcvarsall.bat set or changed are handed on, and nothing else" {
  long="KW_CONFIG={\"padding\":\"$(printf 'x%.0s' $(seq 1 9000))\"}"
  dump "$workspace/before" '=C:=C:\a' "$long" 'INCLUDE=' 'Path=C:\Windows' 'TEMP=D:\a\_temp'
  dump "$workspace/after" '=C:=C:\b' "$long" 'INCLUDE=C:\VS\include' 'LIB=C:\Program Files\VS\lib' 'Path=C:\VS\bin;C:\Windows' 'TEMP=D:\a\_temp'
  : >"$workspace/env"
  KW_BEFORE="$workspace/before" KW_AFTER="$workspace/after" GITHUB_ENV="$workspace/env" \
    run "$repository_root/actions/setup/msvc-env.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"5 variable(s) set."* ]]
  [ "$(grep -c '^[A-Za-z]*<<kw_' "$workspace/env")" = "5" ]
  grep -q '^CC<<kw_' "$workspace/env"
  grep -q '^CXX<<kw_' "$workspace/env"
  grep -q '^LIB<<kw_' "$workspace/env"
  grep -qx 'C:\\Program Files\\VS\\lib' "$workspace/env"
  grep -qx 'C:\\VS\\bin;C:\\Windows' "$workspace/env"
  ! grep -q 'KW_CONFIG\|TEMP\|=C:' "$workspace/env"
  ! grep -q $'\r' "$workspace/env"
}

@test "a variable cmd.exe cut off is never handed on" {
  # cmd.exe cuts a variable off at 8191 characters and runs the next one into it, so the same
  # long variable reads differently before and after vcvarsall.bat.
  cut="KW_CONFIG={\"native\":{\"stage-directory\":\"build/kreate/jni-stag$(printf 'x%.0s' $(seq 1 8160))"
  dump "$workspace/before" "${cut}LOCALAPPDATA=C:\\Users\\runner" 'Path=C:\Windows'
  dump "$workspace/after" "${cut}LIB=C:\\Program Files\\VS\\lib" 'Path=C:\VS\bin;C:\Windows'
  : >"$workspace/env"
  KW_BEFORE="$workspace/before" KW_AFTER="$workspace/after" GITHUB_ENV="$workspace/env" \
    run "$repository_root/actions/setup/msvc-env.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::KW_CONFIG is "*" characters long after vcvarsall.bat"* ]]
  [ ! -s "$workspace/env" ]
}

# --- stage ------------------------------------------------------------------------------------

@test "the stage of a runner is kept when it holds its platform" {
  export KW_CONFIG="$(native_config)"
  stage build/kreate/jni-stage konnect-ipc-server windows-x86_64
  stage build/kreate/jni-stage konnect-ipc-client windows-x86_64
  KW_PLATFORM=windows-x86_64 run "$repository_root/actions/native-stage/check.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value directory)" = "./build/kreate/jni-stage" ]
  [[ "$output" == *"staged  konnect-ipc-server  windows-x86_64"* ]]
}

@test "a runner that built another platform than declared is refused" {
  export KW_CONFIG="$(native_config)"
  stage build/kreate/jni-stage konnect-ipc-server windows-x86_64
  KW_PLATFORM=windows-aarch64 run "$repository_root/actions/native-stage/check.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"kreateJniStage staged konnect-ipc-server for windows-x86_64 on a runner that native.runners declares as windows-aarch64."* ]]
}

@test "a stage whose manifest names another platform is refused" {
  export KW_CONFIG="$(native_config)"
  stage build/kreate/jni-stage konnect-ipc-server windows-aarch64 windows-x86_64
  KW_PLATFORM=windows-aarch64 run "$repository_root/actions/native-stage/check.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"names another platform than windows-aarch64"* ]]
}

@test "a stage without a manifest is refused" {
  export KW_CONFIG="$(native_config)"
  stage build/kreate/jni-stage konnect-ipc-server windows-x86_64
  rm build/kreate/jni-stage/konnect-ipc-server/windows-x86_64/native.properties
  KW_PLATFORM=windows-x86_64 run "$repository_root/actions/native-stage/check.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"has no native.properties"* ]]
}

@test "a manifest with Windows line endings is read" {
  export KW_CONFIG="$(native_config)"
  stage build/kreate/jni-stage konnect-ipc-server windows-x86_64
  sed -i 's/$/\r/' build/kreate/jni-stage/konnect-ipc-server/windows-x86_64/native.properties
  KW_PLATFORM=windows-x86_64 run "$repository_root/actions/native-stage/check.sh"
  [ "$status" -eq 0 ]
}

@test "a stage task that staged nothing fails" {
  export KW_CONFIG="$(native_config)"
  KW_PLATFORM=windows-x86_64 run "$repository_root/actions/native-stage/check.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"kreateJniStage left no stage in ./build/kreate/jni-stage"* ]]
  mkdir -p build/kreate/jni-stage
  KW_PLATFORM=windows-x86_64 run "$repository_root/actions/native-stage/check.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"kreateJniStage staged nothing"* ]]
}

# --- collect ----------------------------------------------------------------------------------

@test "the collected stages reach the build with their platforms" {
  export KW_CONFIG="$(native_config)"
  for artifact in konnect-ipc-server konnect-ipc-client; do
    stage "$workspace/natives" "$artifact" windows-x86_64
    stage "$workspace/natives" "$artifact" windows-aarch64
  done
  KW_DIRECTORY="$workspace/natives" run "$repository_root/actions/native-collect/collect.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value args)" = "[\"--stacktrace\",\"-Pkreate.jni.stage=$workspace/natives\",\"-Pkreate.jni.publishPlatforms=windows-x86_64,windows-aarch64\"]" ]
  [ "$(output_value build-invocations)" = '[["assemble","kreateJniNativeJars"]]' ]
}

@test "a platform that no runner delivered stops the publishing job" {
  export KW_CONFIG="$(native_config)"
  stage "$workspace/natives" konnect-ipc-server windows-x86_64
  KW_DIRECTORY="$workspace/natives" run "$repository_root/actions/native-collect/collect.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"The stage of konnect-ipc-server has no windows-aarch64."* ]]
}

@test "a platform that no runner was declared for stops the publishing job" {
  export KW_CONFIG="$(native_config)"
  stage "$workspace/natives" konnect-ipc-server windows-x86_64
  stage "$workspace/natives" konnect-ipc-server windows-aarch64
  stage "$workspace/natives" konnect-ipc-server linux-x86_64
  KW_DIRECTORY="$workspace/natives" run "$repository_root/actions/native-collect/collect.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"holds linux-x86_64, which native.runners does not list"* ]]
}

@test "no stage at all stops the publishing job" {
  export KW_CONFIG="$(native_config)"
  KW_DIRECTORY="$workspace/natives" run "$repository_root/actions/native-collect/collect.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No native runner left a stage"* ]]
}

@test "empty property names and build tasks pass nothing more" {
  export KW_CONFIG="$(native_config | jq --compact-output '.native["stage-property"] = "" | .native["platforms-property"] = "" | .native["build-tasks"] = ["assemble"]')"
  stage "$workspace/natives" konnect-ipc-server windows-x86_64
  stage "$workspace/natives" konnect-ipc-server windows-aarch64
  KW_DIRECTORY="$workspace/natives" run "$repository_root/actions/native-collect/collect.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value args)" = '["--stacktrace"]' ]
  [ "$(output_value build-invocations)" = '[["assemble"]]' ]
}

# --- release ----------------------------------------------------------------------------------

@test "discovery of a release with natives names the platforms and uploads them first" {
  fake_gradlew
  export KW_CONFIG="$(native_config)"
  export FAKE_GRADLE_OUTPUT="KW|com/example/konnect-ipc-server|konnect-ipc-server|1.0.0|:ipc-server:publishMavenPublicationToDavilsRepository
KW|com/example/konnect-ipc-server-windows-aarch64|konnect-ipc-server-windows-aarch64|1.0.0|:ipc-server:publishKreateNativeWindowsAarch64PublicationToDavilsRepository
KW|com/example/konnect-core|konnect-core|1.0.0|:core:publishMavenPublicationToDavilsRepository
KW|com/example/konnect-ipc-server-windows-x86_64|konnect-ipc-server-windows-x86_64|1.0.0|:ipc-server:publishKreateNativeWindowsX8664PublicationToDavilsRepository"
  run "$repository_root/actions/publications/discover.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "$workspace/gradle-invocations")" == *"-Pkreate.jni.publishPlatforms=windows-x86_64,windows-aarch64"* ]]
  [ "$(output_value publications | jq --raw-output '[.[].artifact] | join(",")')" = \
    "konnect-ipc-server-windows-aarch64,konnect-ipc-server-windows-x86_64,konnect-ipc-server,konnect-core" ]
}

@test "discovery without natives asks Gradle as before and keeps the order" {
  fake_gradlew
  export KW_CONFIG="$(default_config | jq --compact-output '.run = {"native-stages": []}')"
  export FAKE_GRADLE_OUTPUT="KW|com/example/b|b|1.0.0|:b:publish
KW|com/example/a-windows-x86_64|a-windows-x86_64|1.0.0|:a:publish"
  run "$repository_root/actions/publications/discover.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$workspace/gradle-invocations")" = "kotlinWorkflowPublications --init-script $repository_root/actions/publications/list-publications.init.gradle.kts -PkotlinWorkflow.repository=Davils --no-configuration-cache --quiet" ]
  [ "$(output_value publications | jq --raw-output '[.[].artifact] | join(",")')" = "b,a-windows-x86_64" ]
}

@test "the upload takes the arguments of the collected natives" {
  fake_gradlew
  export KW_CONFIG="$(native_config)"
  KW_TASKS='[":ipc-server:publishKreateNativeWindowsX8664PublicationToDavilsRepository"]' \
    KW_ARGS='["--stacktrace", "-Pkreate.jni.stage=/tmp/natives"]' KW_SNAPSHOT=true \
    KW_MAVEN_USERNAME=user KW_MAVEN_PASSWORD=secret \
    run "$repository_root/actions/publish/publish.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$workspace/gradle-invocations")" = ":ipc-server:publishKreateNativeWindowsX8664PublicationToDavilsRepository --stacktrace -Pkreate.jni.stage=/tmp/natives --no-configuration-cache" ]
}
