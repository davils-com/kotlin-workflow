#!/usr/bin/env bats

load helpers

setup() {
  setup_workspace
  mkdir -p .github/workflows actions/a
  export KW_ROOT="$workspace"
}

teardown() {
  teardown_workspace
}

workflow() {
  printf 'jobs:\n  a:\n    steps:\n%s\n' "$1" >.github/workflows/a.yml
}

check() {
  run "$repository_root/scripts/check-pins.sh"
}

@test "a pinned action with a version comment and a self reference pass" {
  workflow '      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: $/actions/setup'
  check
  [ "$status" -eq 0 ]
}

@test "a tag instead of a commit is refused" {
  workflow '      - uses: actions/checkout@v7 # v7.0.1'
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"not pinned to a full commit SHA"* ]]
}

@test "a pin without a version comment is refused" {
  workflow '      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1'
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"names no version"* ]]
}

@test "a relative reference is refused" {
  workflow '      - uses: ./actions/setup'
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"Use \$/ for this repository"* ]]
}

@test "one action pinned to two commits is refused" {
  workflow '      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: actions/checkout@0000000000000000000000000000000000000000 # v7.0.0'
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"more than one commit: actions/checkout"* ]]
}

@test "two paths of one repository at one commit pass" {
  workflow '      - uses: gradle/actions/setup-gradle@8da46b539cd8fe6ab27ca75128919a18d757604c # v6.4.1
      - uses: gradle/actions/dependency-submission@8da46b539cd8fe6ab27ca75128919a18d757604c # v6.4.1'
  check
  [ "$status" -eq 0 ]
}
