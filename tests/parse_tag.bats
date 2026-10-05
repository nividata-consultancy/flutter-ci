#!/usr/bin/env bats
load helpers/common

setup() { setup_tmp; }
teardown() { teardown_tmp; }

@test "uat tag" {
  run "$SCRIPTS/parse_tag.sh" v1.4.0-beta.1
  [ "$status" -eq 0 ]
  [[ "$output" == *"ENVIRONMENT=uat"* ]]
  [[ "$output" == *"VERSION_NAME=1.4.0"* ]]
  [[ "$output" == *"VERSION_NAME_FULL=1.4.0-beta.1"* ]]
  [[ "$output" == *"IS_PRERELEASE=true"* ]]
}

@test "prod tag" {
  run "$SCRIPTS/parse_tag.sh" v1.4.0
  [ "$status" -eq 0 ]
  [[ "$output" == *"ENVIRONMENT=prod"* ]]
  [[ "$output" == *"VERSION_NAME=1.4.0"$'\n'* ]]
  [[ "$output" == *"VERSION_NAME_FULL=1.4.0"$'\n'* ]]
  [[ "$output" == *"IS_PRERELEASE=false"* ]]
}

@test "multi-digit components" {
  run "$SCRIPTS/parse_tag.sh" v10.20.300-beta.42
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERSION_NAME=10.20.300"* ]]
  [[ "$output" == *"VERSION_NAME_FULL=10.20.300-beta.42"* ]]
}

@test "refs/tags/ prefix is stripped" {
  run "$SCRIPTS/parse_tag.sh" refs/tags/v2.0.0
  [ "$status" -eq 0 ]
  [[ "$output" == *"TAG=v2.0.0"* ]]
}

@test "invalid tags are rejected with guidance" {
  for tag in v1.4 v1.4.0-rc1 v1.4.0-beta v1.4.0-beta.x v1.4.0-beta.1.2 1.4.0 V1.4.0 v1.4.0.1 "v1.4.0 " v1.4.0+5 release-1; do
    run "$SCRIPTS/parse_tag.sh" "$tag"
    [ "$status" -eq 1 ] || { echo "accepted: '$tag'"; return 1; }
    [[ "$output" == *"ERROR:"*"RELEASES.md#tag-format"* ]]
  done
}

@test "empty tag fails" {
  run "$SCRIPTS/parse_tag.sh" ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"No tag given"* ]]
}

@test "GitHub mode uses ::error::" {
  GITHUB_ACTIONS=true run "$SCRIPTS/parse_tag.sh" v1.4
  [ "$status" -eq 1 ]
  [[ "$output" == "::error::"* ]]
}

@test "library mode sets variables" {
  source "$SCRIPTS/parse_tag.sh"
  parse_tag v3.1.4-beta.7
  [ "$ENVIRONMENT" = uat ]
  [ "$VERSION_NAME" = 3.1.4 ]
  [ "$VERSION_NAME_FULL" = 3.1.4-beta.7 ]
  [ "$IS_PRERELEASE" = true ]
}
