# Shared helpers of the script tests.

repository_root="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

setup_workspace() {
  workspace="$(mktemp -d)"
  export GITHUB_OUTPUT="$workspace/output"
  export GITHUB_STEP_SUMMARY="$workspace/summary"
  : >"$GITHUB_OUTPUT"
  : >"$GITHUB_STEP_SUMMARY"
  cd "$workspace"
}

teardown_workspace() {
  rm -rf "$workspace"
}

output_value() {
  sed -n "s/^$1=//p" "$GITHUB_OUTPUT" | tail -n 1
}

# A stand-in for the Gradle wrapper that records what it was asked to run and with which secrets.
fake_gradlew() {
  cat >"$workspace/gradlew" <<'SCRIPT'
#!/usr/bin/env bash
echo "$*" >>"$(dirname "$0")/gradle-invocations"
env | grep -E '^(DAVILS_MAVEN_|KREATE_SNAPSHOT|ORG_GRADLE_PROJECT_signing|CUSTOM_)' | sort >>"$(dirname "$0")/gradle-environment" || true
if [ -n "${FAKE_GRADLE_OUTPUT:-}" ]; then printf '%s\n' "$FAKE_GRADLE_OUTPUT"; fi
SCRIPT
  chmod +x "$workspace/gradlew"
}

# Serves $workspace/repository over HTTP and sets $repository_url.
serve_repository() {
  mkdir -p "$workspace/repository"
  local port
  port="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$workspace/repository" >/dev/null 2>&1 &
  server_pid=$!
  repository_url="http://127.0.0.1:$port"
  local attempt
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if curl --silent --output /dev/null "$repository_url/"; then return 0; fi
    sleep 0.2
  done
  return 1
}

stop_repository() {
  if [ -n "${server_pid:-}" ]; then kill "$server_pid" 2>/dev/null || true; fi
}

# publish_artifact <path> <artifact> <version> <packaging> [listed]
publish_artifact() {
  local directory="$workspace/repository/$1/$3"
  mkdir -p "$directory"
  echo "<project><packaging>$4</packaging></project>" >"$directory/$2-$3.pom"
  echo "signature" >"$directory/$2-$3.pom.asc"
  if [ "$4" != "pom" ]; then
    echo "jar" >"$directory/$2-$3.jar"
    echo "signature" >"$directory/$2-$3.jar.asc"
  fi
  if [ "${5:-listed}" = "listed" ]; then
    echo "<metadata><versioning><versions><version>$3</version></versions></versioning></metadata>" \
      >"$workspace/repository/$1/maven-metadata.xml"
  fi
}

default_config() {
  yq --output-format=json '.' "$repository_root/actions/plan/defaults.yml"
}
