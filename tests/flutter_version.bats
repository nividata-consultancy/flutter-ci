#!/usr/bin/env bats
load helpers/common

setup() { setup_tmp; }
teardown() { teardown_tmp; }

@test ".fvmrc" {
  printf '{\n  "flutter": "3.24.5"\n}\n' >"$TMP/.fvmrc"
  run "$SCRIPTS/flutter_version.sh" "$TMP"
  [ "$status" -eq 0 ]
  [ "$output" = "3.24.5" ]
}

@test ".fvmrc with @channel suffix" {
  printf '{"flutter": "3.24.5@stable"}\n' >"$TMP/.fvmrc"
  run "$SCRIPTS/flutter_version.sh" "$TMP"
  [ "$output" = "3.24.5" ]
}

@test "pubspec environment.flutter" {
  printf 'name: x\nenvironment:\n  sdk: ^3.5.0\n  flutter: "3.27.1"\n' >"$TMP/pubspec.yaml"
  run "$SCRIPTS/flutter_version.sh" "$TMP"
  [ "$status" -eq 0 ]
  [ "$output" = "3.27.1" ]
}

@test ".fvmrc wins over pubspec when no file is configured" {
  printf '{"flutter": "3.24.5"}\n' >"$TMP/.fvmrc"
  printf 'name: x\nenvironment:\n  flutter: 3.27.1\n' >"$TMP/pubspec.yaml"
  run "$SCRIPTS/flutter_version.sh" "$TMP"
  [ "$output" = "3.24.5" ]
}

@test "explicit file choice is honored" {
  printf '{"flutter": "3.24.5"}\n' >"$TMP/.fvmrc"
  printf 'name: x\nenvironment:\n  flutter: 3.27.1\n' >"$TMP/pubspec.yaml"
  run "$SCRIPTS/flutter_version.sh" "$TMP" pubspec.yaml
  [ "$output" = "3.27.1" ]
}

@test "pre-release version selects beta channel" {
  printf '{"flutter": "3.27.0-0.1.pre"}\n' >"$TMP/.fvmrc"
  source "$SCRIPTS/flutter_version.sh"
  detect_flutter_version "$TMP"
  [ "$FLUTTER_VERSION" = "3.27.0-0.1.pre" ]
  [ "$FLUTTER_CHANNEL" = beta ]
}

@test "pubspec range constraint is rejected" {
  printf 'name: x\nenvironment:\n  flutter: ">=3.22.0"\n' >"$TMP/pubspec.yaml"
  run "$SCRIPTS/flutter_version.sh" "$TMP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be an exact release"* ]]
}

@test "channel name in .fvmrc is rejected" {
  printf '{"flutter": "stable"}\n' >"$TMP/.fvmrc"
  run "$SCRIPTS/flutter_version.sh" "$TMP"
  [ "$status" -eq 1 ]
}

@test "nothing found fails with guidance" {
  printf 'name: x\nenvironment:\n  sdk: ^3.5.0\n' >"$TMP/pubspec.yaml"
  run "$SCRIPTS/flutter_version.sh" "$TMP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Could not find the Flutter version"* ]]
}

@test "configured .fvmrc missing fails" {
  run "$SCRIPTS/flutter_version.sh" "$TMP" .fvmrc
  [ "$status" -eq 1 ]
  [[ "$output" == *".fvmrc does not exist"* ]]
}
