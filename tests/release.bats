#!/usr/bin/env bats

load helpers

setup() {
  setup_workspace
  publications='[{"path":"com/example/library","artifact":"library","task":":publishMavenPublicationToDavilsRepository"},{"path":"com/example/plugin/com.example.plugin.gradle.plugin","artifact":"com.example.plugin.gradle.plugin","task":":publishPluginMarkerMavenPublicationToDavilsRepository"}]'
}

teardown() {
  stop_repository
  teardown_workspace
}

gate_repository() {
  git init --quiet --bare --initial-branch=main origin
  git clone --quiet origin checkout 2>/dev/null
  cd checkout
  git -c user.name=t -c user.email=t@example.com commit --quiet --allow-empty -m first
  git push --quiet origin HEAD:main
  echo "version=$1" >gradle.properties
  git add gradle.properties
  git -c user.name=t -c user.email=t@example.com commit --quiet -m version
  export GITHUB_SHA
  GITHUB_SHA="$(git rev-parse HEAD)"
}

gate() {
  KW_CONFIG="$(default_config | jq --compact-output "$1")" KW_VERSION="${2:-}" run "$repository_root/actions/release-gate/gate.sh"
}

@test "the gate releases a tag that is on main and matches the declared version" {
  gate_repository 1.2.0
  git push --quiet origin HEAD:main
  gate '.' 1.2.0
  [ "$status" -eq 0 ]
  [ "$(output_value version)" = "1.2.0" ]
}

@test "the gate refuses a commit that is not on main" {
  gate_repository 1.2.0
  gate '.' 1.2.0
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not on main"* ]]
}

@test "the gate refuses a tag that differs from the declared version" {
  gate_repository 1.2.0
  git push --quiet origin HEAD:main
  gate '.' 1.3.0
  [ "$status" -eq 1 ]
  [[ "$output" == *"declares version=1.2.0"* ]]
}

@test "the gate refuses a snapshot" {
  gate_repository 1.2.0
  git push --quiet origin HEAD:main
  gate '.' 1.2.0-SNAPSHOT
  [ "$status" -eq 1 ]
  [[ "$output" == *"is a snapshot"* ]]
}

@test "the gate accepts a declared snapshot version for its release tag" {
  gate_repository 1.2.0-SNAPSHOT
  git push --quiet origin HEAD:main
  gate '.' 1.2.0
  [ "$status" -eq 0 ]
}

@test "the gate rules can be switched off" {
  gate_repository 9.9.9
  gate '.release.gate.branch = "" | .release.gate["version-file"] = ""' 1.2.0
  [ "$status" -eq 0 ]
  [ "$(output_value version)" = "1.2.0" ]
}

@test "a dry run rehearses the declared version and only warns about the branch" {
  gate_repository 1.2.0
  gate '.release["dry-run"] = true'
  [ "$status" -eq 0 ]
  [ "$(output_value version)" = "1.2.0" ]
  [[ "$output" == *"A real release would stop here"* ]]
}

@test "without a tag and without a dry run there is nothing to release" {
  gate_repository 1.2.0
  gate '.'
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing to release"* ]]
}

preflight() {
  KW_PUBLICATIONS="$publications" KW_REPOSITORY_URL="$repository_url" KW_VERSION="$1" run "$repository_root/actions/publications/preflight.sh"
}

@test "the preflight returns every task while nothing is published" {
  serve_repository
  preflight 1.0.0
  [ "$status" -eq 0 ]
  [ "$(output_value tasks | jq 'length')" = "2" ]
}

@test "the preflight skips a publication that is complete" {
  serve_repository
  publish_artifact com/example/library library 1.0.0 jar
  preflight 1.0.0
  [ "$status" -eq 0 ]
  [ "$(output_value tasks | jq --raw-output '.[0]')" = ":publishPluginMarkerMavenPublicationToDavilsRepository" ]
  [ "$(output_value tasks | jq 'length')" = "1" ]
  [[ "$output" == *"complete  library 1.0.0"* ]]
}

@test "the preflight treats another released version as free" {
  serve_repository
  publish_artifact com/example/library library 0.9.0 jar
  preflight 1.0.0
  [ "$status" -eq 0 ]
  [ "$(output_value tasks | jq 'length')" = "2" ]
}

@test "the preflight stops on a publication that was uploaded half way" {
  serve_repository
  publish_artifact com/example/library library 1.0.0 jar unlisted
  preflight 1.0.0
  [ "$status" -eq 1 ]
  [[ "$output" == *"stopped half way"* ]]
  [[ "$output" == *"com/example/library/1.0.0"* ]]
}

@test "the preflight cannot decide when the repository does not answer" {
  KW_PUBLICATIONS="$publications" KW_REPOSITORY_URL="http://127.0.0.1:9" KW_VERSION=1.0.0 run "$repository_root/actions/publications/preflight.sh"
  [ "$status" -ne 0 ]
}

smoke() {
  KW_PUBLICATIONS="$publications" KW_REPOSITORY_URL="$repository_url" KW_VERSION=1.0.0 KW_SIGNED="${1:-true}" KW_DIRECTORY="$workspace/downloads" run "$repository_root/actions/download-release/download.sh"
}

@test "the smoke check finds a complete signed release" {
  serve_repository
  publish_artifact com/example/library library 1.0.0 jar
  publish_artifact com/example/plugin/com.example.plugin.gradle.plugin com.example.plugin.gradle.plugin 1.0.0 pom
  smoke
  [ "$status" -eq 0 ]
  [ -s "$workspace/downloads/library-1.0.0.jar" ]
  [ -s "$workspace/downloads/library-1.0.0.jar.asc" ]
  [ ! -e "$workspace/downloads/com.example.plugin.gradle.plugin-1.0.0.jar" ]
}

@test "the smoke check misses a signature" {
  serve_repository
  publish_artifact com/example/library library 1.0.0 jar
  publish_artifact com/example/plugin/com.example.plugin.gradle.plugin com.example.plugin.gradle.plugin 1.0.0 pom
  rm "$workspace/repository/com/example/library/1.0.0/library-1.0.0.jar.asc"
  smoke
  [ "$status" -eq 1 ]
  [[ "$output" == *"library-1.0.0.jar.asc is missing"* ]]
}

@test "the smoke check of an unsigned release asks for no signature" {
  serve_repository
  publish_artifact com/example/library library 1.0.0 jar
  publish_artifact com/example/plugin/com.example.plugin.gradle.plugin com.example.plugin.gradle.plugin 1.0.0 pom
  rm "$workspace"/repository/com/example/library/1.0.0/*.asc
  smoke false
  [ "$status" -eq 0 ]
}

discover() {
  KW_CONFIG="$(default_config | jq --compact-output "$1")" run "$repository_root/actions/publications/discover.sh"
}

@test "explicit discovery returns the configured publications" {
  discover ".release.publications.discovery = \"explicit\" | .release.publications.list = $publications"
  [ "$status" -eq 0 ]
  [ "$(output_value publications | jq 'length')" = "2" ]
}

@test "explicit discovery refuses an incomplete entry" {
  discover '.release.publications.discovery = "explicit" | .release.publications.list = [{"path": "com/example/library"}]'
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs a path, an artifact and a task"* ]]
}

@test "automatic discovery reads the publications Gradle prints" {
  fake_gradlew
  export FAKE_GRADLE_OUTPUT='KW|com/example/library|library|1.0.0|:publishMavenPublicationToDavilsRepository'
  discover '.'
  [ "$status" -eq 0 ]
  [ "$(output_value publications | jq --raw-output '.[0].task')" = ":publishMavenPublicationToDavilsRepository" ]
  grep -q -- "-PkotlinWorkflow.repository=Davils" "$workspace/gradle-invocations"
}

@test "a build without publications cannot be released" {
  fake_gradlew
  discover '.'
  [ "$status" -eq 1 ]
  [[ "$output" == *"no publication to release"* ]]
}

publish() {
  KW_CONFIG="$(default_config | jq --compact-output "${1:-.}")" KW_TASKS='[":a:publish", ":b:publish"]' run "$repository_root/actions/publish/publish.sh"
}

@test "a snapshot upload carries the token and the snapshot switch, and no signing key" {
  fake_gradlew
  export KW_MAVEN_USERNAME=name KW_MAVEN_PASSWORD=secret KW_SNAPSHOT=true KW_SIGNING_KEY=key
  publish
  [ "$status" -eq 0 ]
  grep -q "DAVILS_MAVEN_NAME=name" "$workspace/gradle-environment"
  grep -q "DAVILS_MAVEN_SECRET=secret" "$workspace/gradle-environment"
  grep -q "KREATE_SNAPSHOT=true" "$workspace/gradle-environment"
  ! grep -q "signingInMemoryKey" "$workspace/gradle-environment"
}

@test "a release upload signs and runs every task on its own, without the configuration cache" {
  fake_gradlew
  export KW_MAVEN_USERNAME=name KW_MAVEN_PASSWORD=secret KW_SIGNING_KEY=key KW_SIGNING_KEY_ID=id KW_SIGNING_PASSWORD=pass
  publish
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$workspace/gradle-invocations" | tr -d ' ')" = "2" ]
  [ "$(sed -n 1p "$workspace/gradle-invocations")" = ":a:publish --stacktrace --no-configuration-cache" ]
  grep -q "ORG_GRADLE_PROJECT_signingInMemoryKey=key" "$workspace/gradle-environment"
  ! grep -q "KREATE_SNAPSHOT" "$workspace/gradle-environment"
}

@test "the token reaches the build under the names the project configures" {
  fake_gradlew
  export KW_MAVEN_USERNAME=name KW_MAVEN_PASSWORD=secret KW_SNAPSHOT=true
  publish '.publish["username-env"] = "CUSTOM_USER" | .publish["password-env"] = "CUSTOM_PASS"'
  [ "$status" -eq 0 ]
  grep -q "CUSTOM_USER=name" "$workspace/gradle-environment"
}

@test "an empty token stops the upload before Gradle runs" {
  fake_gradlew
  export KW_MAVEN_USERNAME= KW_MAVEN_PASSWORD=secret KW_SNAPSHOT=true
  publish
  [ "$status" -eq 1 ]
  [[ "$output" == *"The repository token is empty"* ]]
  [ ! -e "$workspace/gradle-invocations" ]
}

@test "a release without a signing key stops unless signing is switched off" {
  fake_gradlew
  export KW_MAVEN_USERNAME=name KW_MAVEN_PASSWORD=secret
  publish
  [ "$status" -eq 1 ]
  [[ "$output" == *"The signing key is empty"* ]]
  publish '.release.sign = false'
  [ "$status" -eq 0 ]
}

@test "an invalid variable name is refused" {
  fake_gradlew
  export KW_MAVEN_USERNAME=name KW_MAVEN_PASSWORD=secret
  publish '.publish["username-env"] = "BAD NAME"'
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a valid name"* ]]
}
