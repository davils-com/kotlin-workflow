#!/usr/bin/env bats

load helpers

setup() {
  setup_workspace
  unset KW_CONFIG KW_STAGES KW_DRY_RUN KW_CHANGED_FILES KW_CRON KW_PR_DRAFT
  export KW_CONFIG_FILE="$workspace/kotlin-workflow.yml"
}

teardown() {
  teardown_workspace
}

plan() {
  run "$repository_root/actions/plan/plan.sh"
}

pull_request() {
  export KW_EVENT_NAME=pull_request KW_REF=refs/pull/7/merge KW_REF_NAME=7/merge
}

push_to() {
  export KW_EVENT_NAME=push KW_REF="refs/heads/$1" KW_REF_NAME="$1"
}

tag() {
  export KW_EVENT_NAME=push KW_REF="refs/tags/$1" KW_REF_NAME="$1"
}

stage() {
  output_value stages | jq --raw-output ".\"$1\""
}

config() {
  output_value config | jq --raw-output "$1"
}

@test "a pull request checks on Ubuntu and reviews dependencies only" {
  pull_request
  plan
  [ "$status" -eq 0 ]
  [ "$(output_value event)" = "pull-request" ]
  [ "$(stage check)" = "true" ]
  [ "$(stage security)" = "true" ]
  [ "$(stage snapshot)" = "false" ]
  [ "$(output_value matrix | jq 'length')" = "1" ]
  [ "$(config '.security.gradle.enabled')" = "false" ]
  [ "$(config '.security["dependency-review"].enabled')" = "true" ]
  [ "$(config '.run["cache-mode"]')" = "read-only" ]
}

@test "a push to develop publishes a snapshot and writes the cache" {
  push_to develop
  plan
  [ "$status" -eq 0 ]
  [ "$(output_value event)" = "push-develop" ]
  [ "$(stage snapshot)" = "true" ]
  [ "$(stage release)" = "false" ]
  [ "$(config '.run["cache-mode"]')" = "read-write" ]
}

@test "a push to a feature branch checks and never writes the cache" {
  push_to feature/login
  plan
  [ "$status" -eq 0 ]
  [ "$(output_value event)" = "push-other" ]
  [ "$(stage check)" = "true" ]
  [ "$(stage snapshot)" = "false" ]
  [ "$(config '.run["cache-mode"]')" = "read-only" ]
}

@test "a tag releases and hands the version to the build" {
  tag 4.2.0
  plan
  [ "$status" -eq 0 ]
  [ "$(output_value event)" = "tag" ]
  [ "$(output_value version)" = "4.2.0" ]
  [ "$(stage release)" = "true" ]
  [ "$(config '.env.CI_COMMIT_TAG')" = "4.2.0" ]
}

@test "a tag with a v is accepted and the build sees the plain version" {
  tag v1.5.0
  plan
  [ "$status" -eq 0 ]
  [ "$(output_value version)" = "1.5.0" ]
  [ "$(config '.env.CI_COMMIT_TAG')" = "1.5.0" ]
}

@test "a tag prefix is removed from the version" {
  tag library-2.0.0
  export KW_CONFIG='release: { tag: { prefix: "library-" } }'
  plan
  [ "$status" -eq 0 ]
  [ "$(output_value version)" = "2.0.0" ]
}

@test "the project file overrides the defaults" {
  pull_request
  cat >"$KW_CONFIG_FILE" <<'YAML'
jdk:
  version: "21"
check:
  tasks: [verify]
YAML
  plan
  [ "$status" -eq 0 ]
  [ "$(config '.jdk.version')" = "21" ]
  [ "$(config '.check.tasks | join(",")')" = "verify" ]
  [ "$(config '.jdk.distribution')" = "temurin" ]
}

@test "the config input wins over the project file" {
  pull_request
  echo 'jdk: { version: "21" }' >"$KW_CONFIG_FILE"
  export KW_CONFIG='jdk: { version: "17" }'
  plan
  [ "$status" -eq 0 ]
  [ "$(config '.jdk.version')" = "17" ]
}

@test "a number is accepted where a string is expected" {
  pull_request
  export KW_CONFIG='jdk: { version: 21 }'
  plan
  [ "$status" -eq 0 ]
  [ "$(config '.jdk.version')" = "21" ]
  [ "$(config '.jdk.version | type')" = "string" ]
}

@test "an unknown option stops the plan and names its path" {
  pull_request
  export KW_CONFIG='check: { taskz: [check] }'
  plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"check.taskz: unknown option"* ]]
}

@test "a value of the wrong type stops the plan" {
  pull_request
  export KW_CONFIG='check: { tasks: check }'
  plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"check.tasks: expected array, got string"* ]]
}

@test "every problem of a configuration is reported at once" {
  pull_request
  export KW_CONFIG='{ check: { taskz: [] }, jdk: { version: [] } }'
  plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"check.taskz"* ]]
  [[ "$output" == *"jdk.version"* ]]
}

@test "environment variables are free-form" {
  pull_request
  export KW_CONFIG='env: { KREATE_REQUIRE_CMAKE: "true" }'
  plan
  [ "$status" -eq 0 ]
  [ "$(config '.env.KREATE_REQUIRE_CMAKE')" = "true" ]
}

@test "the policy of an event widens the operating system matrix" {
  push_to develop
  export KW_CONFIG='policy: { push-develop: { os: [ubuntu-latest, macos-latest, windows-latest] } }'
  plan
  [ "$status" -eq 0 ]
  [ "$(output_value matrix | jq 'length')" = "3" ]
  [ "$(output_value matrix | jq --raw-output '.[0].primary')" = "true" ]
  [ "$(output_value matrix | jq --raw-output '.[2].primary')" = "false" ]
  [ "$(output_value matrix | jq --raw-output '.[1]["runs-on"]')" = "macos-latest" ]
}

@test "the overrides of an event change any option for that event only" {
  export KW_CONFIG='policy: { push-main: { overrides: { check: { reproducible: { enabled: true } } } } }'
  push_to main
  plan
  [ "$status" -eq 0 ]
  [ "$(config '.check.reproducible.enabled')" = "true" ]
  : >"$GITHUB_OUTPUT"
  pull_request
  plan
  [ "$status" -eq 0 ]
  [ "$(config '.check.reproducible.enabled')" = "false" ]
}

@test "overrides are validated like the rest and cannot change the policy" {
  pull_request
  export KW_CONFIG='policy: { pull-request: { overrides: { check: { nope: 1 }, policy: {} } } }'
  plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"policy.pull-request.overrides.check.nope: unknown option"* ]]
  [[ "$output" == *"overrides cannot change the policy"* ]]
}

@test "a change of documentation alone skips every stage" {
  pull_request
  printf 'README.md\ndocs/guide/setup.md\n' >"$workspace/changed"
  export KW_CHANGED_FILES="$workspace/changed"
  plan
  [ "$status" -eq 0 ]
  [ "$(stage check)" = "false" ]
  [ "$(stage security)" = "false" ]
  grep -q "only ignored paths changed" "$GITHUB_STEP_SUMMARY"
}

@test "a change of documentation on main still builds the docs" {
  push_to main
  printf 'docs/topics/Home.md\n' >"$workspace/changed"
  export KW_CHANGED_FILES="$workspace/changed"
  plan
  [ "$status" -eq 0 ]
  [ "$(stage check)" = "false" ]
  [ "$(stage docs)" = "true" ]
}

@test "one changed source file keeps every stage" {
  pull_request
  printf 'README.md\nsrc/main/kotlin/App.kt\n' >"$workspace/changed"
  export KW_CHANGED_FILES="$workspace/changed"
  plan
  [ "$status" -eq 0 ]
  [ "$(stage check)" = "true" ]
}

@test "a tag is never skipped for its paths" {
  tag 1.0.0
  printf 'README.md\n' >"$workspace/changed"
  export KW_CHANGED_FILES="$workspace/changed"
  plan
  [ "$status" -eq 0 ]
  [ "$(stage release)" = "true" ]
}

@test "a draft runs unless the project switches drafts off" {
  pull_request
  export KW_PR_DRAFT=true
  plan
  [ "$(stage check)" = "true" ]
  : >"$GITHUB_OUTPUT"
  export KW_CONFIG='pull-request: { drafts: false }'
  plan
  [ "$status" -eq 0 ]
  [ "$(stage check)" = "false" ]
}

@test "a schedule starts the stages its cron is mapped to" {
  export KW_EVENT_NAME=schedule KW_REF=refs/heads/main KW_REF_NAME=main KW_CRON='0 4 * * 0'
  export KW_CONFIG='schedule: { crons: { "0 4 * * 0": [benchmark] } }'
  plan
  [ "$status" -eq 0 ]
  [ "$(stage benchmark)" = "true" ]
  [ "$(stage security)" = "false" ]
}

@test "a schedule without a mapping runs the full security stage" {
  export KW_EVENT_NAME=schedule KW_REF=refs/heads/main KW_REF_NAME=main KW_CRON='0 4 * * 1'
  plan
  [ "$status" -eq 0 ]
  [ "$(stage security)" = "true" ]
  [ "$(config '.security.gradle.enabled')" = "true" ]
}

@test "the stages input replaces the policy and is validated" {
  export KW_EVENT_NAME=workflow_dispatch KW_REF=refs/heads/develop KW_REF_NAME=develop
  export KW_STAGES='release, docs'
  plan
  [ "$status" -eq 0 ]
  [ "$(stage release)" = "true" ]
  [ "$(stage docs)" = "true" ]
  [ "$(stage check)" = "false" ]
  : >"$GITHUB_OUTPUT"
  export KW_STAGES='deploy'
  plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown stage: deploy"* ]]
}

@test "a dry run reaches the release configuration" {
  export KW_EVENT_NAME=workflow_dispatch KW_REF=refs/heads/develop KW_REF_NAME=develop KW_DRY_RUN=true
  plan
  [ "$status" -eq 0 ]
  [ "$(config '.release["dry-run"]')" = "true" ]
}

@test "a custom develop branch is recognised" {
  push_to next
  export KW_CONFIG='branches: { develop: next }'
  plan
  [ "$status" -eq 0 ]
  [ "$(output_value event)" = "push-develop" ]
}

@test "another configuration version is refused" {
  pull_request
  export KW_CONFIG='version: 2'
  plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"only version 1 is supported"* ]]
}

@test "a pull request offers the dependencies stage and knows whether the catalog changed" {
  pull_request
  printf 'gradle/libs.versions.toml\n' >"$workspace/changed"
  export KW_CHANGED_FILES="$workspace/changed"
  plan
  [ "$status" -eq 0 ]
  [ "$(stage dependencies)" = "true" ]
  [ "$(config '.run["catalog-changed"]')" = "true" ]
}

@test "a pull request that leaves the catalog alone does not ask for a repair" {
  pull_request
  printf 'src/main/kotlin/App.kt\n' >"$workspace/changed"
  export KW_CHANGED_FILES="$workspace/changed"
  plan
  [ "$(config '.run["catalog-changed"]')" = "false" ]
}

@test "a change of the Gradle wrapper asks for a repair too" {
  pull_request
  printf 'gradle/wrapper/gradle-wrapper.properties\n' >"$workspace/changed"
  export KW_CHANGED_FILES="$workspace/changed"
  plan
  [ "$(config '.run["catalog-changed"]')" = "true" ]
}

@test "an unknown list of changes is treated as a change of the catalog" {
  pull_request
  plan
  [ "$(config '.run["catalog-changed"]')" = "true" ]
}

@test "a project names its own catalog" {
  pull_request
  printf 'build/versions.toml\n' >"$workspace/changed"
  export KW_CHANGED_FILES="$workspace/changed"
  export KW_CONFIG='dependencies: { catalog: build/versions.toml }'
  plan
  [ "$(config '.run["catalog-changed"]')" = "true" ]
}
