#!/usr/bin/env bats
load helpers/common

ANDROID="$BATS_TEST_DIRNAME/../scripts/android"

setup() { setup_tmp; }
teardown() { teardown_tmp; }

@test "build args without flavor" {
  BUILD_NAME=1.4.0-beta.1 BUILD_NUMBER=42 FLUTTER_CI_PRINT_ARGS=1 run "$ANDROID/build.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"--flavor"* ]]
  [[ "$output" == *"--build-name=1.4.0-beta.1"* ]]
  [[ "$output" == *"--build-number=42"* ]]
  [[ "$output" != *"--obfuscate"* ]]
}

@test "build args with flavor, target, defines and obfuscation" {
  FLAVOR=uat TARGET=lib/main_uat.dart DART_DEFINE_PATH=/tmp/d.json OBFUSCATE=true \
    BUILD_NAME=1.4.0 BUILD_NUMBER=1 FLUTTER_CI_PRINT_ARGS=1 run "$ANDROID/build.sh"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "--release" ]
  [ "${lines[1]}" = "--flavor" ]
  [ "${lines[2]}" = "uat" ]
  [ "${lines[3]}" = "--target" ]
  [ "${lines[4]}" = "lib/main_uat.dart" ]
  [[ "$output" == *"--dart-define-from-file=/tmp/d.json"* ]]
  [[ "$output" == *"--obfuscate"*"--split-debug-info=build/flutter-ci-debug-info"* ]]
}

@test "resolve: version and build number come from pubspec" {
  mkdir -p "$TMP/app/.ci"
  write_valid_config "$TMP/app/.ci/config.yaml"
  printf '{"flutter":"3.24.5"}' >"$TMP/app/.fvmrc"
  printf 'name: x\nversion: 1.0.0+42\n' >"$TMP/app/pubspec.yaml"
  cd "$TMP/app"
  GITHUB_OUTPUT="$TMP/out" GITHUB_REF_TYPE=tag GITHUB_REF_NAME=v1.0.0-beta.2 GITHUB_RUN_NUMBER=5 run "$ANDROID/resolve.sh"
  [ "$status" -eq 0 ]
  grep -qx 'BUILD_NUMBER=42' "$TMP/out"
  grep -qx 'APP_VERSION=1.0.0' "$TMP/out"
}

@test "resolve: tag version must match pubspec" {
  mkdir -p "$TMP/app/.ci"
  write_valid_config "$TMP/app/.ci/config.yaml"
  printf '{"flutter":"3.24.5"}' >"$TMP/app/.fvmrc"
  printf 'name: x\nversion: 1.0.0+42\n' >"$TMP/app/pubspec.yaml"
  cd "$TMP/app"
  GITHUB_REF_TYPE=tag GITHUB_REF_NAME=v1.1.0-beta.1 run "$ANDROID/resolve.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Tag v1.1.0-beta.1 is for version 1.1.0, but pubspec.yaml says 1.0.0+42"* ]]
}

@test "resolve: refuses branch builds and tag override without dry-run" {
  mkdir -p "$TMP/app/.ci"
  write_valid_config "$TMP/app/.ci/config.yaml"
  cd "$TMP/app"
  GITHUB_REF_TYPE=branch GITHUB_REF=refs/heads/main GITHUB_RUN_NUMBER=1 run "$ANDROID/resolve.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be triggered by pushing a tag"* ]]
  TAG_OVERRIDE=v1.0.0 DRY_RUN=false GITHUB_RUN_NUMBER=1 run "$ANDROID/resolve.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"only allowed together with dry-run"* ]]
}

@test "signing: missing secrets fail, or warn with --allow-missing" {
  mkdir -p "$TMP/app/android" && cd "$TMP/app"
  run "$ANDROID/signing.sh" write
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing signing secrets"* ]]
  run "$ANDROID/signing.sh" write --allow-missing
  [ "$status" -eq 0 ]
  [ ! -f android/key.properties ]
}

@test "signing: writes key.properties and cleans up" {
  command -v keytool >/dev/null || skip "keytool not installed"
  mkdir -p "$TMP/app/android" && cd "$TMP/app"
  keytool -genkeypair -keystore "$TMP/k.jks" -storepass 'p@ss\word' -keypass 'p@ss\word' \
    -alias upload -dname CN=test -keyalg RSA -keysize 2048 -validity 1 >/dev/null 2>&1
  export RUNNER_TEMP="$TMP/runner"
  ANDROID_KEYSTORE_BASE64="$(base64 <"$TMP/k.jks")" ANDROID_KEYSTORE_PASSWORD='p@ss\word' \
    ANDROID_KEY_ALIAS=upload ANDROID_KEY_PASSWORD='p@ss\word' run "$ANDROID/signing.sh" write
  [ "$status" -eq 0 ]
  [[ "$output" != *"p@ss"* ]]
  grep -qx 'storePassword=p@ss\\\\word' android/key.properties
  grep -qx 'keyAlias=upload' android/key.properties
  [ -f "$RUNNER_TEMP/flutter-ci/upload-keystore.jks" ]
  run "$ANDROID/signing.sh" cleanup
  [ ! -f android/key.properties ]
  [ ! -f "$RUNNER_TEMP/flutter-ci/upload-keystore.jks" ]
}

@test "signing: wrong password is reported" {
  command -v keytool >/dev/null || skip "keytool not installed"
  mkdir -p "$TMP/app/android" && cd "$TMP/app"
  keytool -genkeypair -keystore "$TMP/k.jks" -storepass right1 -keypass right1 \
    -alias upload -dname CN=test -keyalg RSA -keysize 2048 -validity 1 >/dev/null 2>&1
  RUNNER_TEMP="$TMP/runner" ANDROID_KEYSTORE_BASE64="$(base64 <"$TMP/k.jks")" ANDROID_KEYSTORE_PASSWORD=wrong1 \
    ANDROID_KEY_ALIAS=upload ANDROID_KEY_PASSWORD=wrong1 run "$ANDROID/signing.sh" write
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not be opened"* ]]
  [ ! -f android/key.properties ]
}

@test "signing: refuses a committed key.properties" {
  git_q init "$TMP/app" && cd "$TMP/app" && mkdir -p android && echo x > android/key.properties
  git_q add android/key.properties
  ANDROID_KEYSTORE_BASE64=eA== ANDROID_KEYSTORE_PASSWORD=a ANDROID_KEY_ALIAS=b ANDROID_KEY_PASSWORD=c \
    run "$ANDROID/signing.sh" write
  [ "$status" -eq 1 ]
  [[ "$output" == *"is committed to git"* ]]
}

@test "dart defines: committed file, secret, and missing" {
  mkdir -p "$TMP/app/env" && cd "$TMP/app"
  echo '{"A":"1"}' > env/uat.json
  run "$SCRIPTS/dart_defines.sh" . uat env/uat.json
  [ "$status" -eq 0 ]
  [[ "$output" == */env/uat.json ]]
  RUNNER_TEMP="$TMP/rt" DART_DEFINES_PROD_JSON='{"B":"2"}' run "$SCRIPTS/dart_defines.sh" . prod env/prod.json
  [ "$status" -eq 0 ]
  [ "$(cat "${lines[${#lines[@]}-1]}")" = '{"B":"2"}' ]
  RUNNER_TEMP="$TMP/rt" DART_DEFINES_PROD_JSON_BASE64="$(printf '{"C":"3"}' | base64)" run "$SCRIPTS/dart_defines.sh" . prod
  [ "$(cat "${lines[${#lines[@]}-1]}")" = '{"C":"3"}' ]
  run "$SCRIPTS/dart_defines.sh" . prod env/prod.json
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not in the repo"* ]]
  DART_DEFINES_PROD_JSON='not json' run "$SCRIPTS/dart_defines.sh" . prod
  [ "$status" -eq 1 ]
}
