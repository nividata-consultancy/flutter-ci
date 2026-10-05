#!/bin/bash
# Xcode Cloud: ci_post_clone.sh (called by the app's tiny bootstrap in
# ios/ci_scripts/ci_post_clone.sh).
#
#  1. Require CI_TAG (the workflow must start on Tag Changes).
#  2. Parse tag, validate .ci/config.yaml, run the prod guard (if
#     app.prod_branches is set).
#  3. Install Flutter at the app's pinned version, precache, pub get.
#  4. Dart defines from the repo or DART_DEFINES_<ENV>_JSON_BASE64.
#  5. Generate ios/Flutter/Environment.xcconfig, copy GoogleService-Info.plist.
#  6. flutter build ios --config-only (versions + defines into Generated.xcconfig).
#  7. pod install (when the app uses CocoaPods).
#  8. Save the parsed values to .flutter-ci/state.env for ci_post_xcodebuild.sh.
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
# shellcheck source=scripts/common/dart_defines.sh
source "$FLUTTER_CI_DIR/scripts/common/dart_defines.sh"
# shellcheck source=scripts/common/ios_xcconfig.sh
source "$FLUTTER_CI_DIR/scripts/common/ios_xcconfig.sh"
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
    notify_slack "❌ ${APP_NAME:-iOS app} iOS ${CI_TAG:-?} (build ${CI_BUILD_NUMBER:-?}) failed in ci_post_clone.sh"
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
      "XCODE_CLOUD_SETUP.md#4-create-the-workflow"
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
  local build_number="${CI_BUILD_NUMBER:?CI_BUILD_NUMBER is not set}"
  local commit="${CI_COMMIT:-$(git rev-parse HEAD)}"
  log_info "[$ENV_LABEL] $TAG → version $VERSION_NAME ($build_number), Flutter $FLUTTER_VERSION"

  if [[ "$ENVIRONMENT" == "prod" && -n "$PROD_BRANCHES" ]]; then
    log_step "Prod guard"
    # shellcheck disable=SC2086 # space-separated list
    prod_guard "$commit" $PROD_BRANCHES || exit 1
  fi

  # 3. Flutter
  install_flutter
  log_step "flutter precache --ios && flutter pub get"
  flutter precache --ios
  flutter pub get

  # 4. Dart defines
  local defines
  defines="$(resolve_dart_defines . "$ENVIRONMENT" "$DART_DEFINE_FILE")" || exit 1

  # 5. Environment.xcconfig + GoogleService-Info.plist
  log_step "Generating ios/Flutter/Environment.xcconfig"
  ios_xcconfig "$CONFIG_PATH" "$ENVIRONMENT" >ios/Flutter/Environment.xcconfig
  cat ios/Flutter/Environment.xcconfig
  # Only matters when the config sets a name, icon or build settings.
  if [[ "$(grep -cv '^//' ios/Flutter/Environment.xcconfig)" -gt 0 ]] \
    && ! grep -q 'Environment.xcconfig' ios/Flutter/Release.xcconfig; then
    log_warn "environments.$ENVIRONMENT.ios sets a name/icon/build settings, but ios/Flutter/Release.xcconfig does not include Environment.xcconfig, so they are ignored. See $(doc_url XCODE_CLOUD_SETUP.md#optional-different-name-and-icon-for-uat)"
  fi
  if [[ -n "$IOS_GOOGLE_SERVICE_INFO" ]]; then
    [[ -f "$IOS_GOOGLE_SERVICE_INFO" ]] \
      || die "environments.$ENVIRONMENT.ios.google_service_info '$IOS_GOOGLE_SERVICE_INFO' does not exist." "CONFIG_REFERENCE.md#ios"
    cp "$IOS_GOOGLE_SERVICE_INFO" ios/Runner/GoogleService-Info.plist
    log_info "Copied $IOS_GOOGLE_SERVICE_INFO to ios/Runner/GoogleService-Info.plist"
  fi

  # 6. flutter build ios --config-only
  local args=(build ios --config-only --release --no-codesign
    "--build-name=$VERSION_NAME" "--build-number=$build_number")
  [[ -n "$defines" ]] && args+=("--dart-define-from-file=$defines")
  [[ -n "$IOS_TARGET" ]] && args+=(--target "$IOS_TARGET")
  if [[ "$OBFUSCATE" == "true" ]]; then
    args+=(--obfuscate "--split-debug-info=$APP_ROOT/build/flutter-ci-debug-info")
  fi
  log_step "flutter ${args[*]}"
  flutter "${args[@]}"

  # 7. CocoaPods
  if [[ -f ios/Podfile ]]; then
    install_cocoapods
    log_step "pod install"
    (cd ios && { pod install || pod install --repo-update; }) \
      || die "pod install failed." "TROUBLESHOOTING.md#pod-install-fails"
  else
    log_info "No ios/Podfile; skipping pod install (Swift Package Manager)."
  fi

  # 8. State for ci_post_xcodebuild.sh
  mkdir -p "$(dirname "$STATE_FILE")"
  {
    print_context
    printf 'BUILD_NUMBER=%q\nCOMMIT=%q\nAPP_ROOT=%q\n' "$build_number" "$commit" "$APP_ROOT"
  } >"$STATE_FILE"
  log_info "Saved build state to $STATE_FILE"
  log_step "ci_post_clone.sh done: [$ENV_LABEL] $TAG ($build_number)"
}

main "$@"
