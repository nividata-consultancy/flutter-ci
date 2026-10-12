#!/bin/bash
# Xcode Cloud: ci_post_clone.sh (called by the app's tiny bootstrap in
# ios/ci_scripts/ci_post_clone.sh).
#
#  1. Require CI_TAG (the workflow must start on Tag Changes).
#  2. Parse tag, validate .ci/config.yaml, run the prod guard (if
#     app.prod_branches is set).
#  3. Install Flutter at the app's pinned version, precache, pub get, and the
#     FlutterFire CLI if a Crashlytics build phase needs it.
#  4. flutter build ios --config-only (version + build number from pubspec.yaml,
#     environments.<env>.build_args such as --dart-define-from-file into
#     Generated.xcconfig).
#  5. pod install (when the app uses CocoaPods).
#  6. Save the parsed values to .flutter-ci/state.env for ci_post_xcodebuild.sh.
#
# Optional env (Xcode Cloud workflow → Environment):
#   FLUTTER_CI_APP_DIR      app root inside the repo (default: .)
#   FLUTTER_CI_CONFIG_PATH  config path relative to the app root (default: .ci/config.yaml)
#   SLACK_WEBHOOK_URL       failure notifications
set -euo pipefail

FLUTTER_CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/common/context.sh
source "$FLUTTER_CI_DIR/scripts/common/context.sh"
# shellcheck source=scripts/common/prod_guard.sh
source "$FLUTTER_CI_DIR/scripts/common/prod_guard.sh"
# shellcheck source=scripts/common/notify_slack.sh
source "$FLUTTER_CI_DIR/scripts/common/notify_slack.sh"

REPO="${CI_PRIMARY_REPOSITORY_PATH:?CI_PRIMARY_REPOSITORY_PATH is not set; this script runs on Xcode Cloud}"
APP_ROOT="$REPO/${FLUTTER_CI_APP_DIR:-.}"
CONFIG_PATH="${FLUTTER_CI_CONFIG_PATH:-.ci/config.yaml}"
STATE_FILE="$REPO/.flutter-ci/state.env"
FLUTTER_HOME="${FLUTTER_CI_FLUTTER_HOME:-$HOME/flutter}"

on_exit() {
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    notify_slack "❌ ${APP_NAME:-iOS app} iOS ${CI_TAG:-?} (build ${BUILD_NUMBER:-?}) failed in ci_post_clone.sh"
  fi
}
trap on_exit EXIT

install_flutter() {
  if [[ -x "$FLUTTER_HOME/bin/flutter" ]]; then
    local have
    have="$(git -C "$FLUTTER_HOME" describe --tags --exact-match HEAD 2>/dev/null || true)"
    if [[ "$have" != "$FLUTTER_VERSION" ]]; then
      die "$FLUTTER_HOME already contains Flutter '${have:-unknown}', but the app pins $FLUTTER_VERSION. Remove it or set FLUTTER_CI_FLUTTER_HOME." \
        "TROUBLESHOOTING.md#flutter-version-mismatch"
    fi
    log_info "Flutter $FLUTTER_VERSION already installed at $FLUTTER_HOME."
  else
    log_step "Installing Flutter $FLUTTER_VERSION into $FLUTTER_HOME"
    git clone --quiet --depth 1 -b "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_HOME" \
      || die "Could not clone Flutter $FLUTTER_VERSION. Is it a real release tag? (see https://docs.flutter.dev/release/archive)" \
        "TROUBLESHOOTING.md#flutter-version-mismatch"
  fi
  export PATH="$FLUTTER_HOME/bin:$PATH"
  flutter config --no-analytics >/dev/null 2>&1 || true
  flutter --version
}

install_cocoapods() {
  if command -v pod >/dev/null 2>&1; then return 0; fi
  log_step "Installing CocoaPods with Homebrew"
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install cocoapods \
    || die "Could not install CocoaPods." "TROUBLESHOOTING.md#pod-install-fails"
}

main() {
  # 1. Tag
  if [[ -z "${CI_TAG:-}" ]]; then
    die "CI_TAG is not set. flutter-ci builds only run for tags: set the workflow Start Condition to 'Tag Changes' (custom tags beginning with 'v') and push a tag such as v1.4.0-beta.1. Manual builds of a branch are not supported." \
      "IOS_SETUP.md#step-5-create-the-xcode-cloud-workflow"
  fi
  cd "$APP_ROOT"
  # Keep the downloaded library and state out of `git status`.
  if [[ -d "$REPO/.git/info" ]] && ! grep -qx '/.flutter-ci/' "$REPO/.git/info/exclude" 2>/dev/null; then
    echo '/.flutter-ci/' >>"$REPO/.git/info/exclude"
  fi

  # 2. Tag + config + prod guard
  log_step "Resolving build context for $CI_TAG"
  resolve_context . "$CONFIG_PATH" "$CI_TAG" ios || exit 1
  [[ "$CONFIG_PATH" == /* ]] || CONFIG_PATH="$APP_ROOT/$CONFIG_PATH"
  if [[ "$IOS_ENABLED" != "true" ]]; then
    trap - EXIT
    die "iOS is disabled for '$ENVIRONMENT' (environments.$ENVIRONMENT.ios.enabled: false in .ci/config.yaml), so this build stops here on purpose. Nothing is built or sent to TestFlight. Xcode Cloud cannot skip a tag build, which is why it shows as failed." \
      "CONFIG_REFERENCE.md#platform-switches"
  fi
  local build_number="$BUILD_NUMBER"     # from pubspec.yaml (version: X.Y.Z+N)
  local commit="${CI_COMMIT:-$(git rev-parse HEAD)}"
  log_info "[$ENV_LABEL] $TAG → version $APP_VERSION ($build_number), Flutter $FLUTTER_VERSION"
  # Xcode Cloud replaces the build number with its own (CI_BUILD_NUMBER) when it
  # prepares the build for TestFlight; only its "Next Build Number" setting changes that.
  if [[ -n "${CI_BUILD_NUMBER:-}" && "$CI_BUILD_NUMBER" != "$build_number" ]]; then
    log_warn "TestFlight will show build $CI_BUILD_NUMBER (the Xcode Cloud build number), not $build_number from pubspec.yaml. To line them up, set App Store Connect → your app → Xcode Cloud → Settings → Build Number → Next Build Number."
  fi

  if [[ "$ENVIRONMENT" == "prod" && -n "$PROD_BRANCHES" ]]; then
    log_step "Prod guard"
    # shellcheck disable=SC2086 # space-separated list
    prod_guard "$commit" $PROD_BRANCHES || exit 1
  fi

  # With iOS flavors the Xcode Cloud workflow must archive the flavor's scheme;
  # otherwise it would quietly build another app.
  if [[ -n "$IOS_FLAVOR" && -n "${CI_XCODE_SCHEME:-}" && "$CI_XCODE_SCHEME" != "$IOS_FLAVOR" ]]; then
    die "This Xcode Cloud workflow archives the scheme '$CI_XCODE_SCHEME', but environments.$ENVIRONMENT.ios.flavor is '$IOS_FLAVOR'. In the workflow's Archive action, choose the scheme '$IOS_FLAVOR' (and check FLUTTER_CI_CONFIG_PATH)." \
      "IOS_SETUP.md#apps-with-flavors"
  fi

  # Without this check a missing main file only shows up much later, in the
  # archive step, as "Command PhaseScriptExecution failed".
  local target="${IOS_TARGET:-lib/main.dart}"
  if [[ ! -f "$target" ]]; then
    die "The iOS entry file '$target' does not exist. If the app uses flavor main files (e.g. lib/main_myapp.dart), set environments.$ENVIRONMENT.ios.target in the config." \
      "TROUBLESHOOTING.md#phasescriptexecution-failed-ios"
  fi

  # 3. Flutter
  install_flutter
  log_step "flutter precache --ios && flutter pub get"
  flutter precache --ios
  flutter pub get

  # Apps set up with `flutterfire configure` get an Xcode build phase that runs
  # `flutterfire upload-crashlytics-symbols`. Xcode Cloud doesn't have that CLI,
  # so the archive would fail with "PhaseScriptExecution failed".
  if grep -q "flutterfire upload-crashlytics-symbols" ios/Runner.xcodeproj/project.pbxproj 2>/dev/null; then
    log_step "Installing the FlutterFire CLI (used by a Crashlytics build phase)"
    dart pub global activate flutterfire_cli \
      || die "Could not install the FlutterFire CLI (dart pub global activate flutterfire_cli)." \
        "TROUBLESHOOTING.md#phasescriptexecution-failed-ios"
    export PATH="$PATH:$HOME/.pub-cache/bin"
    flutterfire --version || true
  fi

  # 4. flutter build ios --config-only
  local args=(build ios --config-only --release --no-codesign
    "--build-name=$APP_VERSION" "--build-number=$build_number")
  [[ -n "$IOS_TARGET" ]] && args+=(--target "$IOS_TARGET")
  [[ -n "$IOS_FLAVOR" ]] && args+=(--flavor "$IOS_FLAVOR")
  # Extra flags (environments.<env>.build_args) land in Generated.xcconfig,
  # which the Xcode archive reads.
  local arg
  while IFS= read -r arg; do
    [[ -n "$arg" ]] && args+=("$arg")
  done <<<"${BUILD_ARGS:-}"
  log_step "flutter ${args[*]}"
  flutter "${args[@]}"

  # 5. CocoaPods
  if [[ -f ios/Podfile ]]; then
    install_cocoapods
    log_step "pod install"
    (cd ios && { pod install || pod install --repo-update; }) \
      || die "pod install failed." "TROUBLESHOOTING.md#pod-install-fails"
  else
    log_info "No ios/Podfile; skipping pod install (Swift Package Manager)."
  fi

  # 6. State for ci_post_xcodebuild.sh
  mkdir -p "$(dirname "$STATE_FILE")"
  {
    print_context
    printf 'COMMIT=%q\nAPP_ROOT=%q\n' "$commit" "$APP_ROOT"
  } >"$STATE_FILE"
  log_info "Saved build state to $STATE_FILE"
  log_step "ci_post_clone.sh done: [$ENV_LABEL] $TAG ($build_number)"
}

main "$@"
