# Shared bats helpers.
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
SCRIPTS="$REPO_ROOT/scripts/common"

setup_tmp() {
  TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/flutter-ci.XXXXXX")"
  # Never emit GitHub workflow commands from tests unless a test opts in.
  unset GITHUB_ACTIONS GITHUB_OUTPUT
}

teardown_tmp() {
  [[ -n "${TMP:-}" && -d "$TMP" ]] && rm -rf "$TMP"
}

# write_valid_config <path>
write_valid_config() {
  mkdir -p "$(dirname "$1")"
  cat >"$1" <<'YAML'
version: 1
app:
  name: MyApp
  flutter_version_file: .fvmrc
  java_version: "17"
  prod_branches: [main]
  build_number_offset: 100
  run_tests: true
  run_analyze: false
  obfuscate: false
  android_package_name: com.example.myapp
environments:
  uat:
    dart_define_file: env/uat.json
    android:
      flavor: uat
      target: lib/main.dart
      artifacts: [aab, apk]
      destinations:
        playstore: { enabled: true, tracks: [internal] }
        firebase: { enabled: true, groups: "qa-team" }
        drive: { enabled: true, folder_id: "0AbCdEfGhIjKlMnOp" }
    ios:
      display_name: "MyApp UAT"
      app_icon: AppIcon-UAT
      google_service_info: ios/config/uat/GoogleService-Info.plist
      build_settings:
        MY_SETTING: "abc"
  prod:
    dart_define_file: env/prod.json
    android:
      artifacts: [aab]
      destinations:
        playstore: { enabled: true, tracks: [internal, production] }
        firebase: { enabled: false, groups: "qa-team" }
        drive: { enabled: false, folder_id: "SHARED_DRIVE_FOLDER_ID" }
    ios:
      display_name: "MyApp"
      app_icon: AppIcon
YAML
}

# git_quiet <args> — git without noise and with a fixed identity.
git_q() {
  git -c user.email=ci@example.com -c user.name=CI -c init.defaultBranch=main \
    -c commit.gpgsign=false -c tag.gpgsign=false "$@" >/dev/null 2>&1
}
