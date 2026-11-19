#!/usr/bin/env bats

load helpers

setup() {
  setup_workspace
  export GITHUB_ENV="$workspace/env"
  : >"$GITHUB_ENV"
}

teardown() {
  teardown_workspace
}

@test "gradle runs every invocation on its own with the shared arguments" {
  fake_gradlew
  KW_INVOCATIONS='[["check", "koverXmlReport"], ["integrationTest"]]' KW_ARGS='["--stacktrace"]' KW_CONFIGURATION_CACHE=true run "$repository_root/actions/gradle/run.sh"
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "$workspace/gradle-invocations")" = "check koverXmlReport --stacktrace --configuration-cache" ]
  [ "$(sed -n 2p "$workspace/gradle-invocations")" = "integrationTest --stacktrace --configuration-cache" ]
}

@test "gradle keeps the configuration cache off when asked" {
  fake_gradlew
  KW_INVOCATIONS='[["assemble"]]' KW_CONFIGURATION_CACHE=false run "$repository_root/actions/gradle/run.sh"
  [ "$(cat "$workspace/gradle-invocations")" = "assemble --no-configuration-cache" ]
}

@test "gradle reads the token it is given as GITHUB_TOKEN, and nothing else" {
  fake_gradlew
  KW_INVOCATIONS='[["check"]]' KW_GITHUB_TOKEN=token run "$repository_root/actions/gradle/run.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$workspace/gradle-environment")" = "GITHUB_TOKEN=token" ]
  [[ "$output" != *token* ]]
}

@test "gradle without a token gets no GITHUB_TOKEN, not even an empty one" {
  fake_gradlew
  env -u GITHUB_TOKEN KW_INVOCATIONS='[["check"]]' KW_GITHUB_TOKEN='' \
    "$repository_root/actions/gradle/run.sh"
  [ ! -s "$workspace/gradle-environment" ]
}

@test "an empty invocation runs nothing" {
  fake_gradlew
  KW_INVOCATIONS='[[], ["check"]]' run "$repository_root/actions/gradle/run.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$workspace/gradle-invocations")" = "check" ]
  rm "$workspace/gradle-invocations"
  KW_INVOCATIONS='[]' run "$repository_root/actions/gradle/run.sh"
  [ "$status" -eq 0 ]
  [ ! -e "$workspace/gradle-invocations" ]
}

@test "the env map is exported, multi-line values included" {
  KW_CONFIG='{"env": {"A": "one", "B": "two\nlines", "C": 3}}' run "$repository_root/actions/setup/export-env.sh"
  [ "$status" -eq 0 ]
  grep -q '^A<<kw_' "$GITHUB_ENV"
  grep -q '^lines$' "$GITHUB_ENV"
  grep -q '^3$' "$GITHUB_ENV"
}

@test "an invalid variable name in the env map is refused" {
  KW_CONFIG='{"env": {"A B": "x"}}' run "$repository_root/actions/setup/export-env.sh"
  [ "$status" -eq 1 ]
}

@test "the guard refuses local Kreate publications" {
  export GRADLE_USER_HOME="$workspace/gradle-home"
  mkdir -p "$GRADLE_USER_HOME"
  run "$repository_root/actions/setup/guard-local-state.sh"
  [ "$status" -eq 0 ]
  mkdir -p "$GRADLE_USER_HOME/kreate/local"
  run "$repository_root/actions/setup/guard-local-state.sh"
  [ "$status" -eq 1 ]
}

@test "files are found by glob, without version control or Gradle state" {
  mkdir -p a/build/libs b/build/libs .gradle/build/libs
  touch a/build/libs/a.jar b/build/libs/b.jar .gradle/build/libs/c.jar a/build/libs/a.txt
  run "$repository_root/actions/_lib/find-files.sh" '["**/build/libs/*.jar"]'
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | sort | tr '\n' ' ')" = "a/build/libs/a.jar b/build/libs/b.jar " ]
}

sarif() {
  cat <<JSON
{"version": "2.1.0", "runs": [{"tool": {"driver": {"name": "detekt", "rules": [{"id": "$1"}]}}, "results": [{"ruleId": "$1"}]}]}
JSON
}

@test "several SARIF files of one tool become a single run" {
  mkdir -p a/build/reports/detekt/main b/build/reports/detekt/main
  sarif RuleA >a/build/reports/detekt/main/detekt.sarif
  sarif RuleB >b/build/reports/detekt/main/detekt.sarif
  export RUNNER_TEMP="$workspace"
  KW_GLOB='**/build/reports/detekt/**/*.sarif' KW_CATEGORY=detekt run "$repository_root/actions/sarif/collect.sh"
  [ "$status" -eq 0 ]
  merged="$(output_value file)"
  [ "$(jq '.runs | length' "$merged")" = "1" ]
  [ "$(jq '.runs[0].results | length' "$merged")" = "2" ]
  [ "$(jq '.runs[0].tool.driver.rules | length' "$merged")" = "2" ]
}

@test "a finding without a location is filed under the fallback location" {
  mkdir -p build/kreate/assurance/reports
  cat >build/kreate/assurance/reports/report.sarif <<'JSON'
{"version": "2.1.0", "runs": [{"tool": {"driver": {"name": "Kreate", "rules": []}}, "results": [
  {"ruleId": "A"},
  {"ruleId": "B", "locations": []},
  {"ruleId": "C", "locations": [{"physicalLocation": {"artifactLocation": {"uri": "src/Main.kt"}}}]}
]}]}
JSON
  export RUNNER_TEMP="$workspace"
  KW_GLOB='**/report.sarif' KW_CATEGORY=assurance KW_FALLBACK_LOCATION=gradle/libs.versions.toml \
    run "$repository_root/actions/sarif/collect.sh"
  [ "$status" -eq 0 ]
  merged="$(output_value file)"
  uris="$(jq --raw-output '[.runs[0].results[].locations[0].physicalLocation.artifactLocation.uri] | join(" ")' "$merged")"
  [ "$uris" = "gradle/libs.versions.toml gradle/libs.versions.toml src/Main.kt" ]
}

@test "a finding without a location stays as it is without a fallback location" {
  mkdir -p build/kreate/assurance/reports
  echo '{"version": "2.1.0", "runs": [{"tool": {"driver": {"name": "Kreate"}}, "results": [{"ruleId": "A"}]}]}' \
    >build/kreate/assurance/reports/report.sarif
  export RUNNER_TEMP="$workspace"
  KW_GLOB='**/report.sarif' KW_CATEGORY=assurance run "$repository_root/actions/sarif/collect.sh"
  [ "$status" -eq 0 ]
  [ "$(jq '.runs[0].results[0] | has("locations")' "$(output_value file)")" = "false" ]
}

@test "no SARIF file and an empty glob upload nothing" {
  export RUNNER_TEMP="$workspace"
  KW_GLOB='**/*.sarif' KW_CATEGORY=detekt run "$repository_root/actions/sarif/collect.sh"
  [ "$status" -eq 0 ]
  [ -z "$(output_value file)" ]
  : >"$GITHUB_OUTPUT"
  KW_GLOB='' KW_CATEGORY=detekt run "$repository_root/actions/sarif/collect.sh"
  [ -z "$(output_value file)" ]
}

@test "the summary reports tests, coverage and the assurance report" {
  mkdir -p app/build/test-results/test app/build/reports/kover app/build/kreate/assurance/reports
  echo '<testsuite name="a" tests="5" skipped="1" failures="2" errors="0">' >app/build/test-results/test/TEST-a.xml
  echo '<testsuite name="b" tests="3" skipped="0" failures="0" errors="1">' >app/build/test-results/test/TEST-b.xml
  echo '<report><counter type="LINE" missed="10" covered="5"/><counter type="LINE" missed="25" covered="75"/></report>' >app/build/reports/kover/report.xml
  echo 'Assurance passed.' >app/build/kreate/assurance/reports/report.md
  KW_CONFIG="$(default_config | jq --compact-output '.')" run "$repository_root/actions/reports/summary.sh"
  [ "$status" -eq 0 ]
  grep -q '| 8 | 2 | 1 | 1 |' "$GITHUB_STEP_SUMMARY"
  grep -q '75.0 %' "$GITHUB_STEP_SUMMARY"
  grep -q 'Assurance passed.' "$GITHUB_STEP_SUMMARY"
}

failed_report() {
  mkdir -p app/build/test-results/test
  cat >app/build/test-results/test/TEST-com.example.PathTest.xml <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="com.example.PathTest" tests="4" skipped="0" failures="2" errors="1">
  <testcase name="passes" classname="com.example.PathTest" time="0.1"/>
  <testcase name="resolves a path: C:\tools, twice" classname="com.example.PathTest" time="0.2">
    <failure message="expected:&lt;&quot;a/b&quot;&gt; but was:&lt;&quot;a\b&quot;&gt;&#10;second line 100%" type="java.lang.AssertionError">java.lang.AssertionError: expected
	at com.example.PathTest.kt:12</failure>
  </testcase>
  <testcase name="reads a file" classname="com.example.PathTest" time="0.2">
    <error message="No such file &amp; directory" type="java.io.IOException">java.io.IOException</error>
  </testcase>
  <testcase name="times out" classname="com.example.PathTest" time="9">
    <failure type="java.lang.AssertionError">java.lang.AssertionError</failure>
  </testcase>
</testsuite>
XML
}

@test "failed tests become error annotations and a list in the summary" {
  failed_report
  KW_LEG=check-reports-windows-latest KW_CONFIG="$(default_config | jq --compact-output '.')" \
    run "$repository_root/actions/reports/failed-tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *'::error title=Failed test%3A PathTest > resolves a path%3A C%3A\tools%2C twice::expected:<"a/b"> but was:<"a\b">%0Asecond line 100%25'* ]]
  [[ "$output" == *'::error title=Failed test%3A PathTest > reads a file::No such file & directory'* ]]
  [[ "$output" == *'::error title=Failed test%3A PathTest > times out::The test failed without a message.'* ]]
  [[ "$output" != *"passes"* ]]
  grep -q '### Failed tests (check-reports-windows-latest)' "$GITHUB_STEP_SUMMARY"
  grep -q 'com.example.PathTest` > reads a file' "$GITHUB_STEP_SUMMARY"
}

@test "the message of a failed Gradle build starts at what went wrong" {
  mkdir -p app/build/test-results/test
  cat >app/build/test-results/test/TEST-a.xml <<'XML'
<testsuite name="a" tests="1" failures="1">
  <testcase name="builds" classname="a.BuildTest">
    <failure message="Unexpected build execution failure with arguments [jar]&#10;Output:&#10;&gt; Task :jar FAILED&#10;* What went wrong:&#10;CMake configure failed with exit code 1." type="x">trace</failure>
  </testcase>
</testsuite>
XML
  KW_CONFIG="$(default_config | jq --compact-output '.')" run "$repository_root/actions/reports/failed-tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *'::error title=Failed test%3A BuildTest > builds::* What went wrong:%0ACMake configure failed with exit code 1.'* ]]
}

@test "only as many failed tests are named as the limit allows" {
  failed_report
  KW_CONFIG="$(default_config | jq --compact-output '.check.summary["failed-tests"] = 1')" \
    run "$repository_root/actions/reports/failed-tests.sh"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^::error' <<<"$output")" = "1" ]
  [[ "$output" == *'::warning title=More failed tests::2 more tests failed'* ]]
}

@test "no failed test and a limit of zero name nothing" {
  mkdir -p app/build/test-results/test
  echo '<testsuite name="a" tests="1"><testcase name="passes" classname="a"/></testsuite>' >app/build/test-results/test/TEST-a.xml
  KW_CONFIG="$(default_config | jq --compact-output '.')" run "$repository_root/actions/reports/failed-tests.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  failed_report
  KW_CONFIG="$(default_config | jq --compact-output '.check.summary["failed-tests"] = 0')" \
    run "$repository_root/actions/reports/failed-tests.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the summary of a build without reports is empty" {
  KW_CONFIG="$(default_config | jq --compact-output '.')" run "$repository_root/actions/reports/summary.sh"
  [ "$status" -eq 0 ]
  [ ! -s "$GITHUB_STEP_SUMMARY" ]
}

reproducible_gradlew() {
  cat >"$workspace/gradlew" <<SCRIPT
#!/usr/bin/env bash
mkdir -p "\$(dirname "\$0")/build/libs"
$1
SCRIPT
  chmod +x "$workspace/gradlew"
}

@test "two identical builds are reproducible" {
  reproducible_gradlew 'echo fixed >"$(dirname "$0")/build/libs/app.jar"'
  KW_CONFIG="$(default_config | jq --compact-output '.')" run "$repository_root/actions/reproducible/compare.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Both builds produced the same artifacts"* ]]
}

@test "two different builds are reported" {
  reproducible_gradlew 'echo "$RANDOM$RANDOM" >"$(dirname "$0")/build/libs/app.jar"'
  KW_CONFIG="$(default_config | jq --compact-output '.')" run "$repository_root/actions/reproducible/compare.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"produced different artifacts"* ]]
}

cleaning_gradlew() {
  cat >"$workspace/gradlew" <<'SCRIPT'
#!/usr/bin/env bash
root="$(dirname "$0")"
echo "$1" >>"$root/invocations.log"
if [ "$1" = "clean" ]; then rm -rf "$root/build"; exit 0; fi
mkdir -p "$root/build/libs"
echo fixed >"$root/build/libs/app.jar"
SCRIPT
  chmod +x "$workspace/gradlew"
}

@test "each build starts with a clean of its own invocation" {
  cleaning_gradlew
  KW_CONFIG="$(default_config | jq --compact-output '.')" run "$repository_root/actions/reproducible/compare.sh"
  [ "$status" -eq 0 ]
  [ "$(tr '\n' ' ' <invocations.log)" = "clean jar clean jar " ]
}

@test "no clean task leaves the clean out" {
  cleaning_gradlew
  KW_CONFIG="$(default_config | jq --compact-output '.check.reproducible["clean-tasks"] = []')" \
    run "$repository_root/actions/reproducible/compare.sh"
  [ "$status" -eq 0 ]
  [ "$(tr '\n' ' ' <invocations.log)" = "jar jar " ]
}

@test "a reproducibility check without artifacts fails" {
  reproducible_gradlew 'true'
  KW_CONFIG="$(default_config | jq --compact-output '.')" run "$repository_root/actions/reproducible/compare.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"found no artifact"* ]]
}

@test "the consumer build replaces the placeholders and passes the token of a private repository" {
  fake_gradlew
  echo "version=2.0.0" >gradle.properties
  smoke='{"project-dir": "smoke", "tasks": ["detekt"], "args": ["-Pv={version}", "-Pr={repository}"]}'
  KW_CONFIG="$(default_config | jq --compact-output '.')" KW_SMOKE="$smoke" KW_SNAPSHOT=true \
    KW_REPOSITORY_URL=https://repo.example.com/snapshots KW_MAVEN_USERNAME=name KW_MAVEN_PASSWORD=secret \
    run "$repository_root/actions/consumer-build/build.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$workspace/gradle-invocations")" = "-p smoke detekt -Pv=2.0.0-SNAPSHOT -Pr=https://repo.example.com/snapshots --no-configuration-cache" ]
  grep -q "DAVILS_MAVEN_NAME=name" "$workspace/gradle-environment"
}

@test "the consumer build of a release uses the released version" {
  fake_gradlew
  smoke='{"project-dir": "smoke", "tasks": ["build"], "args": ["-Pv={version}"]}'
  KW_CONFIG="$(default_config | jq --compact-output '.')" KW_SMOKE="$smoke" KW_VERSION=3.1.0 \
    KW_REPOSITORY_URL=https://repo.example.com/releases run "$repository_root/actions/consumer-build/build.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$workspace/gradle-invocations")" = "-p smoke build -Pv=3.1.0 --no-configuration-cache" ]
}

@test "a consumer build without a project directory is refused" {
  fake_gradlew
  KW_CONFIG="$(default_config | jq --compact-output '.')" KW_SMOKE='{"project-dir": "", "tasks": [], "args": []}' KW_VERSION=1.0.0 \
    run "$repository_root/actions/consumer-build/build.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"smoke.project-dir is empty"* ]]
}

@test "markdown files are appended to the summary" {
  mkdir -p build/reports
  echo "faster" >build/reports/comparison.md
  KW_GLOB='**/build/reports/*.md' KW_TITLE=Benchmark run "$repository_root/actions/summary-files/append.sh"
  [ "$status" -eq 0 ]
  grep -q "faster" "$GITHUB_STEP_SUMMARY"
  grep -q "### Benchmark" "$GITHUB_STEP_SUMMARY"
}
