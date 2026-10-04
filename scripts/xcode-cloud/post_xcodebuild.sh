#!/bin/bash
# Xcode Cloud: ci_post_xcodebuild.sh (called by the app's bootstrap in
# ios/ci_scripts/ci_post_xcodebuild.sh). Acts only after an archive.
#
# iOS builds go to TestFlight only; the TestFlight post-action in the Xcode
# Cloud workflow distributes them. This script only sends the optional Slack
# notification (SLACK_WEBHOOK_URL) and never fails the build.
set -uo pipefail

FLUTTER_CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/common/notify_slack.sh
source "$FLUTTER_CI_DIR/scripts/common/notify_slack.sh"

STATE_FILE="${CI_PRIMARY_REPOSITORY_PATH:-}/.flutter-ci/state.env"

if [[ "${CI_XCODEBUILD_ACTION:-}" != "archive" ]]; then
  log_info "CI_XCODEBUILD_ACTION is '${CI_XCODEBUILD_ACTION:-}', not 'archive'; nothing to do."
  exit 0
fi

if [[ ! -f "$STATE_FILE" ]]; then
  log_warn "$STATE_FILE is missing; ci_post_clone.sh did not finish. See $(doc_url TROUBLESHOOTING.md#scripts-not-found-or-not-executable)"
  exit 0
fi
# shellcheck source=/dev/null
source "$STATE_FILE"

if [[ -n "${CI_XCODEBUILD_EXIT_CODE:-}" && "${CI_XCODEBUILD_EXIT_CODE}" != "0" ]]; then
  notify_slack "❌ $APP_NAME iOS [$ENV_LABEL] $TAG (build $BUILD_NUMBER): archive failed"
else
  notify_slack "✅ $APP_NAME iOS [$ENV_LABEL] $TAG (build $BUILD_NUMBER) archived; TestFlight processing follows."
fi
exit 0
