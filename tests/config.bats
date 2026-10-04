#!/usr/bin/env bats
load helpers/common

setup() {
  setup_tmp
  CFG="$TMP/.ci/config.yaml"
  write_valid_config "$CFG"
}
teardown() { teardown_tmp; }

# set_yq <expr> — mutate the test config in place.
set_yq() { yq -i e "$1" "$CFG"; }

@test "valid config passes" {
  run "$SCRIPTS/read_config.sh" validate "$CFG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"is valid"* ]]
}

@test "valid config passes for each env" {
  run "$SCRIPTS/read_config.sh" validate "$CFG" uat
  [ "$status" -eq 0 ]
  run "$SCRIPTS/read_config.sh" validate "$CFG" prod
  [ "$status" -eq 0 ]
}

@test "minimal config passes" {
  printf 'version: 1\napp:\n  name: X\nenvironments:\n  uat: {}\n' >"$CFG"
  run "$SCRIPTS/read_config.sh" validate "$CFG" uat
  [ "$status" -eq 0 ]
}

@test "missing file" {
  run "$SCRIPTS/read_config.sh" validate "$TMP/nope.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "invalid YAML" {
  printf 'version: 1\napp: [unclosed\n' >"$CFG"
  run "$SCRIPTS/read_config.sh" validate "$CFG"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not valid YAML"* ]]
}

@test "wrong schema version" {
  set_yq '.version = 2'
  run "$SCRIPTS/read_config.sh" validate "$CFG"
  [ "$status" -eq 1 ]
  [[ "$output" == *"version: 2 is not supported"* ]]
}

@test "missing required keys" {
  printf 'foo: 1\n' >"$CFG"
  run "$SCRIPTS/read_config.sh" validate "$CFG"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown key 'foo'"* ]]
  [[ "$output" == *"version is required"* ]]
  [[ "$output" == *"app is required"* ]]
  [[ "$output" == *"environments is required"* ]]
}

@test "reports all errors at once" {
  set_yq '.app.run_tests = "yes" | .app.build_number_offset = -3 | .app.java_version = "seventeen" | .app.tyop = 1'
  run "$SCRIPTS/read_config.sh" validate "$CFG"
  [ "$status" -eq 1 ]
  [[ "$output" == *"app.run_tests must be true/false"* ]]
  [[ "$output" == *"build_number_offset must be 0 or a positive integer"* ]]
  [[ "$output" == *"java_version must be a major version"* ]]
  [[ "$output" == *"unknown key 'tyop'"* ]]
  [[ "$output" == *"CONFIG_REFERENCE.md"* ]]
}

@test "java_version may be an integer" {
  set_yq '.app.java_version = 21'
  run "$SCRIPTS/read_config.sh" validate "$CFG"
  [ "$status" -eq 0 ]
}

@test "requested env must exist" {
  set_yq 'del(.environments.prod)'
  run "$SCRIPTS/read_config.sh" validate "$CFG" prod
  [ "$status" -eq 1 ]
  [[ "$output" == *"environments.prod is missing"* ]]
}

@test "unknown environment name" {
  set_yq '.environments.staging = {}'
  run "$SCRIPTS/read_config.sh" validate "$CFG"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown key 'staging'"* ]]
}

@test "bad artifacts" {
  set_yq '.environments.uat.android.artifacts = ["ipa"]'
  run "$SCRIPTS/read_config.sh" validate "$CFG"
  [ "$status" -eq 1 ]
  [[ "$output" == *"'ipa' is not supported"* ]]
  [[ "$output" == *"playstore needs 'aab'"* ]]
}

@test "production track is refused" {
  set_yq '.environments.prod.android.destinations.playstore.track = "production"'
  run "$SCRIPTS/read_config.sh" validate "$CFG"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must not be 'production'"* ]]
}

@test "playstore requires package name" {
  set_yq 'del(.app.android_package_name)'
  run "$SCRIPTS/read_config.sh" validate "$CFG"
  [ "$status" -eq 1 ]
  [[ "$output" == *"android_package_name is required"* ]]
}

@test "drive placeholder folder id is refused" {
  set_yq '.environments.uat.android.destinations.drive.folder_id = "SHARED_DRIVE_FOLDER_ID"'
  run "$SCRIPTS/read_config.sh" validate "$CFG"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Shared Drive"* ]]
}

@test "testflight under ios destinations explains where it lives" {
  set_yq '.environments.uat.ios.destinations.testflight = {}'
  run "$SCRIPTS/read_config.sh" validate "$CFG"
  [ "$status" -eq 1 ]
  [[ "$output" == *"configured as a post-action in the Xcode Cloud workflow"* ]]
}

@test "invalid ios build setting name" {
  set_yq '.environments.uat.ios.build_settings."bad-key" = "x"'
  run "$SCRIPTS/read_config.sh" validate "$CFG"
  [ "$status" -eq 1 ]
  [[ "$output" == *"'bad-key' is not a valid build setting name"* ]]
}

@test "firebase without apk only warns" {
  set_yq '.environments.uat.android.artifacts = ["aab"]'
  run "$SCRIPTS/read_config.sh" validate "$CFG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING:"*"linked to Google Play"* ]]
}

@test "get returns false booleans and empty for missing" {
  run "$SCRIPTS/read_config.sh" get "$CFG" '.app.obfuscate'
  [ "$output" = "false" ]
  run "$SCRIPTS/read_config.sh" get "$CFG" '.app.missing'
  [ "$output" = "" ]
}

@test "context resolves android values" {
  printf '{"flutter": "3.24.5"}\n' >"$TMP/.fvmrc"
  run "$SCRIPTS/context.sh" "$TMP" .ci/config.yaml v1.2.3-beta.4 android
  [ "$status" -eq 0 ]
  [[ "$output" == *"ENVIRONMENT=uat"* ]]
  [[ "$output" == *"ENV_LABEL=UAT"* ]]
  [[ "$output" == *"FLUTTER_VERSION=3.24.5"* ]]
  [[ "$output" == *"ANDROID_FLAVOR=uat"* ]]
  [[ "$output" == *"ANDROID_ARTIFACTS=aab\ apk"* ]]
  [[ "$output" == *"BUILD_NUMBER_OFFSET=100"* ]]
  [[ "$output" == *"PLAYSTORE_ENABLED=true"* ]]
  [[ "$output" == *"PLAYSTORE_TRACK=internal"* ]]
  [[ "$output" == *"DRIVE_FOLDER_ID=0AbCdEfGhIjKlMnOp"* ]]
  [[ "$output" == *"PROD_BRANCHES=main"* ]]
}

@test "context resolves ios values and is sourceable" {
  printf '{"flutter": "3.24.5"}\n' >"$TMP/.fvmrc"
  "$SCRIPTS/context.sh" "$TMP" .ci/config.yaml v1.2.3-beta.4 ios >"$TMP/ctx.env"
  source "$TMP/ctx.env"
  [ "$IOS_DISPLAY_NAME" = "MyApp UAT" ]
  [ "$IOS_APP_ICON" = "AppIcon-UAT" ]
  [ "$FIREBASE_ENABLED" = true ]
  [ "$DRIVE_ENABLED" = false ]
}

@test "context writes GITHUB_OUTPUT" {
  printf '{"flutter": "3.24.5"}\n' >"$TMP/.fvmrc"
  GITHUB_OUTPUT="$TMP/out" run "$SCRIPTS/context.sh" "$TMP" .ci/config.yaml v1.2.3 android
  [ "$status" -eq 0 ]
  grep -qx 'ENVIRONMENT=prod' "$TMP/out"
  grep -qx 'ANDROID_FLAVOR=' "$TMP/out"
  grep -qx 'FIREBASE_ENABLED=false' "$TMP/out"
}
