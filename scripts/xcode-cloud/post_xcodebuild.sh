#!/bin/bash
# Xcode Cloud: ci_post_xcodebuild.sh (called by the app's bootstrap in
# ios/ci_scripts/ci_post_xcodebuild.sh). Acts only after an archive.
#
#  1. Write ios/TestFlight/WhatToTest.en-US.txt (<1 KB), first line
#     "[UAT] v1.4.0-beta.1 · abc1234" / "[PROD] v1.4.0 · abc1234".
#  2. Upload the ad hoc IPA to Firebase App Distribution / Google Drive when
#     config lists them for iOS in this environment.
#  3. Optional Slack notification.
#
# Destination and notification failures are logged as errors but do not fail
# the build (so TestFlight still gets it). Set FLUTTER_CI_STRICT=1 to fail.
set -euo pipefail

FLUTTER_CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/common/util.sh
source "$FLUTTER_CI_DIR/scripts/common/util.sh"
# shellcheck source=scripts/common/notify_slack.sh
source "$FLUTTER_CI_DIR/scripts/common/notify_slack.sh"

REPO="${CI_PRIMARY_REPOSITORY_PATH:?CI_PRIMARY_REPOSITORY_PATH is not set; this script runs on Xcode Cloud}"
STATE_FILE="$REPO/.flutter-ci/state.env"

if [[ "${CI_XCODEBUILD_ACTION:-}" != "archive" ]]; then
  log_info "CI_XCODEBUILD_ACTION is '${CI_XCODEBUILD_ACTION:-}', not 'archive'; nothing to do."
  exit 0
fi

[[ -f "$STATE_FILE" ]] || die "$STATE_FILE is missing; ci_post_clone.sh did not finish." "TROUBLESHOOTING.md#scripts-not-found-or-not-executable"
# shellcheck source=/dev/null
source "$STATE_FILE"

if [[ -n "${CI_XCODEBUILD_EXIT_CODE:-}" && "${CI_XCODEBUILD_EXIT_CODE}" != "0" ]]; then
  notify_slack "❌ $APP_NAME iOS [$ENV_LABEL] $TAG (build $BUILD_NUMBER): archive failed"
  exit 0
fi

failures=()
results=()

# 1. TestFlight notes. The TestFlight folder sits next to ci_scripts (ios/).
notes_dir="$APP_ROOT/ios/TestFlight"
mkdir -p "$notes_dir"
if (cd "$APP_ROOT" && "$FLUTTER_CI_DIR/scripts/common/release_notes.sh" "$TAG" --max-bytes 1000 --max-commits 5 --commit "$COMMIT") >"$notes_dir/WhatToTest.en-US.txt"; then
  log_info "TestFlight notes ($(LC_ALL=C wc -c <"$notes_dir/WhatToTest.en-US.txt" | tr -d ' ') bytes):"
  cat "$notes_dir/WhatToTest.en-US.txt"
else
  printf '[%s] %s · %s\n' "$ENV_LABEL" "$TAG" "${COMMIT:0:7}" >"$notes_dir/WhatToTest.en-US.txt"
  log_warn "Could not build release notes from git; wrote the header only."
fi

# 2. Ad hoc destinations
find_ipa() {
  local p="${CI_AD_HOC_SIGNED_APP_PATH:-}"
  if [[ -z "$p" || ! -e "$p" ]]; then
    return 1
  fi
  if [[ -f "$p" && "$p" == *.ipa ]]; then
    printf '%s' "$p"
  else
    find "$p" -maxdepth 3 -name '*.ipa' -print | head -n 1
  fi
}

if [[ "$FIREBASE_ENABLED" == "true" || "$DRIVE_ENABLED" == "true" ]]; then
  ipa="$(find_ipa || true)"
  if [[ -z "$ipa" ]]; then
    log_error "No ad hoc IPA found (CI_AD_HOC_SIGNED_APP_PATH='${CI_AD_HOC_SIGNED_APP_PATH:-}'). Firebase/Drive need an ad hoc export from the archive action." \
      "XCODE_CLOUD_SETUP.md#ad-hoc-ipa-for-firebase-and-drive"
    failures+=("ad hoc IPA missing")
  else
    name="$(slugify "$APP_NAME")-$ENVIRONMENT-$VERSION_NAME_FULL-$BUILD_NUMBER.ipa"
    if [[ "$FIREBASE_ENABLED" == "true" ]]; then
      if "$FLUTTER_CI_DIR/scripts/common/firebase_distribute.sh" --file "$ipa" --app "${FIREBASE_IOS_APP_ID:-}" \
        --groups "$FIREBASE_GROUPS" --testers "$FIREBASE_TESTERS" --release-notes-file "$notes_dir/WhatToTest.en-US.txt" >/dev/null; then
        results+=("Firebase ✓")
      else
        failures+=("Firebase")
      fi
    fi
    if [[ "$DRIVE_ENABLED" == "true" ]]; then
      if link="$("$FLUTTER_CI_DIR/scripts/common/gdrive_upload.sh" "$ipa" "$DRIVE_FOLDER_ID" "$name")"; then
        results+=("Drive ✓ $link")
      else
        failures+=("Drive")
      fi
    fi
  fi
fi

# 3. Notify
msg="✅ $APP_NAME iOS [$ENV_LABEL] $TAG (build $BUILD_NUMBER) archived; TestFlight processing follows."
[[ ${#results[@]} -gt 0 ]] && msg="$msg"$'\n'"${results[*]}"
if [[ ${#failures[@]} -gt 0 ]]; then
  msg="⚠️ $APP_NAME iOS [$ENV_LABEL] $TAG (build $BUILD_NUMBER) archived, but these failed: ${failures[*]}"
fi
notify_slack "$msg"

if [[ ${#failures[@]} -gt 0 ]]; then
  log_error "Failed destinations: ${failures[*]}" "TROUBLESHOOTING.md"
  [[ "${FLUTTER_CI_STRICT:-0}" == "1" ]] && exit 1
fi
exit 0
