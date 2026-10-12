#!/usr/bin/env bats
load helpers/common

XC="$BATS_TEST_DIRNAME/../scripts/xcode-cloud"

setup() {
  setup_tmp
  export CI_PRIMARY_REPOSITORY_PATH="$TMP/repo"
  mkdir -p "$TMP/repo/.flutter-ci" "$TMP/repo/ios"
}
teardown() { teardown_tmp; }

@test "post_clone: requires CI_TAG with guidance" {
  unset CI_TAG
  run "$XC/post_clone.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR: CI_TAG is not set"*"IOS_SETUP.md#step-5-create-the-xcode-cloud-workflow"* ]]
}

@test "post_xcodebuild: no-op unless archive" {
  CI_XCODEBUILD_ACTION=build run "$XC/post_xcodebuild.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to do"* ]]
}

@test "post_xcodebuild: missing state only warns" {
  CI_XCODEBUILD_ACTION=archive run "$XC/post_xcodebuild.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ci_post_clone.sh did not finish"* ]]
}

@test "bootstrap templates are tiny, bash and executable" {
  for f in "$REPO_ROOT"/templates/ios/ci_scripts/*.sh; do
    [ -x "$f" ]
    [ "$(head -n 1 "$f")" = "#!/bin/bash" ]
    [ "$(wc -l <"$f" | tr -d ' ')" -le 12 ]
  done
}
