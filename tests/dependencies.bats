#!/usr/bin/env bats

load helpers

setup() {
  setup_workspace
  git init --quiet --bare --initial-branch=main origin
  git clone --quiet origin checkout 2>/dev/null
  cd checkout
  git config user.name tester
  git config user.email tester@example.com
  mkdir -p gradle app src
  echo "old-lock" >app/gradle.lockfile
  echo "<verification-metadata/>" >gradle/verification-metadata.xml
  echo "fun main() {}" >src/App.kt
  git add -A
  git commit --quiet -m initial
  git push --quiet origin HEAD:main
  git checkout --quiet -b dependabot/gradle/library-2.0.0
  echo 'library = "2.0.0"' >gradle/libs.versions.toml
  git add -A
  git commit --quiet -m "build(deps): bump library"
  git push --quiet origin HEAD:dependabot/gradle/library-2.0.0
  head_sha="$(git rev-parse HEAD)"
  patch="$workspace/records.patch"
  config="$(default_config | jq --compact-output '.dependencies.lock.invocations = [["resolveAndLock", "--write-locks"]]')"
}

teardown() {
  teardown_workspace
}

gradlew() {
  cat >gradlew <<SCRIPT
#!/usr/bin/env bash
echo "\$*" >>"$workspace/gradle-invocations"
$1
SCRIPT
  chmod +x gradlew
}

regenerate() {
  KW_CONFIG="$config" KW_PATCH="$patch" run "$repository_root/actions/dependencies-regenerate/regenerate.sh"
}

apply() {
  KW_CONFIG="$config" KW_PATCH="$patch" KW_EXPECTED_SHA="${1:-$head_sha}" KW_BRANCH=dependabot/gradle/library-2.0.0 \
    KW_PUSH_URL="$workspace/origin" run "$repository_root/actions/dependencies-apply/apply.sh"
}

@test "regenerating runs the lock invocations and the verification, and patches the allowed files only" {
  gradlew 'echo new-lock >app/gradle.lockfile; echo "<verification-metadata>new</verification-metadata>" >gradle/verification-metadata.xml; echo hacked >src/App.kt'
  regenerate
  [ "$status" -eq 0 ]
  [ "$(output_value changed)" = "true" ]
  [ "$(sed -n 1p "$workspace/gradle-invocations")" = "resolveAndLock --write-locks --stacktrace --no-configuration-cache" ]
  [ "$(sed -n 2p "$workspace/gradle-invocations")" = "--write-verification-metadata sha256 check --stacktrace --no-configuration-cache" ]
  grep -q "app/gradle.lockfile" "$patch"
  grep -q "gradle/verification-metadata.xml" "$patch"
  ! grep -q "src/App.kt" "$patch"
}

@test "a new lock file is part of the patch" {
  gradlew 'mkdir -p lib; echo fresh >lib/gradle.lockfile'
  regenerate
  [ "$(output_value changed)" = "true" ]
  grep -q "lib/gradle.lockfile" "$patch"
}

@test "nothing to regenerate leaves an empty patch" {
  gradlew 'true'
  regenerate
  [ "$status" -eq 0 ]
  [ "$(output_value changed)" = "false" ]
  [ ! -s "$patch" ]
}

@test "the verification is skipped for a project without the file" {
  git rm --quiet gradle/verification-metadata.xml
  gradlew 'echo new-lock >app/gradle.lockfile'
  regenerate
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$workspace/gradle-invocations" | tr -d ' ')" = "1" ]
}

@test "a build that fails while its checksums are recorded still yields the patch" {
  gradlew 'echo "<verification-metadata>new</verification-metadata>" >gradle/verification-metadata.xml; case "$*" in *write-verification*) exit 1 ;; esac'
  regenerate
  [ "$status" -eq 0 ]
  [ "$(output_value changed)" = "true" ]
  [[ "$output" == *"The build failed while its checksums were recorded"* ]]
}

@test "a checked patch is committed and pushed to the branch of the pull request" {
  gradlew 'echo new-lock >app/gradle.lockfile'
  regenerate
  git checkout --quiet -- . && rm gradlew
  : >"$GITHUB_OUTPUT"
  apply
  [ "$status" -eq 0 ]
  [ "$(output_value pushed)" = "true" ]
  pushed="$(git --git-dir="$workspace/origin" log -1 --format='%an|%s' dependabot/gradle/library-2.0.0)"
  [ "$pushed" = "github-actions[bot]|build(deps): record locks and checksums" ]
  [ "$(git --git-dir="$workspace/origin" show dependabot/gradle/library-2.0.0:app/gradle.lockfile)" = "new-lock" ]
}

@test "a patch that touches another file is refused and nothing is pushed" {
  echo hacked >src/App.kt
  git diff --binary >"$patch"
  git checkout --quiet -- .
  apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"may not change: src/App.kt"* ]]
  [ "$(git --git-dir="$workspace/origin" rev-parse dependabot/gradle/library-2.0.0)" = "$head_sha" ]
}

@test "a patch that makes a file executable is refused" {
  chmod +x app/gradle.lockfile
  git diff --binary >"$patch"
  git checkout --quiet -- .
  apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"changes the mode"* ]]
}

@test "a patch that deletes a file is refused" {
  rm app/gradle.lockfile
  git diff --binary >"$patch"
  git checkout --quiet -- .
  apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"renames, deletes"* ]]
}

@test "a branch that moved in the meantime is left alone" {
  echo new-lock >app/gradle.lockfile
  git diff --binary >"$patch"
  git checkout --quiet -- .
  apply 0000000000000000000000000000000000000000
  [ "$status" -eq 0 ]
  [ "$(output_value pushed)" = "false" ]
  [[ "$output" == *"The branch moved"* ]]
}

@test "an empty patch commits nothing" {
  : >"$patch"
  apply
  [ "$status" -eq 0 ]
  [ "$(output_value pushed)" = "false" ]
}
