#!/bin/bash
# Write the GitHub job summary and send the optional Slack notification.
# Never fails the job.
#
# Env: STATUS (job.status), ENVIRONMENT, ENV_LABEL, TAG, APP_VERSION,
#   BUILD_NUMBER, DRY_RUN, APP_NAME, DESTINATIONS (newline list of
#   "name|result|link"), RUN_URL, SLACK_WEBHOOK_URL
set -uo pipefail

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common/notify_slack.sh
source "$_DIR/../common/notify_slack.sh"

status="${STATUS:-unknown}"
icon="✅"
[[ "$status" == "success" ]] || icon="❌"
label="${ENV_LABEL:-?}"
version="${APP_VERSION:-?}"
app="${APP_NAME:-app}"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    printf '## %s %s Android [%s] %s\n\n' "$icon" "$app" "$label" "${TAG:-}"
    printf '| | |\n|---|---|\n'
    printf '| Status | %s |\n' "$status"
    printf '| Environment | %s |\n' "${ENVIRONMENT:-?}"
    printf '| Version (pubspec.yaml) | %s |\n' "$version"
    printf '| Build number (versionCode) | %s |\n' "${BUILD_NUMBER:-?}"
    printf '| Dry run | %s |\n' "${DRY_RUN:-false}"
    if [[ -n "${DESTINATIONS:-}" ]]; then
      printf '\n### Destinations\n\n| Destination | Result | Link |\n|---|---|---|\n'
      while IFS='|' read -r name result link; do
        [[ -z "$name" ]] && continue
        printf '| %s | %s | %s |\n' "$name" "$result" "${link:-}"
      done <<<"$DESTINATIONS"
    fi
  } >>"$GITHUB_STEP_SUMMARY"
fi

msg="$icon $app Android [$label] ${TAG:-} (build ${BUILD_NUMBER:-?}) — $status"
[[ "${DRY_RUN:-false}" == "true" ]] && msg="$msg (dry run)"
[[ -n "${RUN_URL:-}" ]] && msg="$msg"$'\n'"$RUN_URL"
notify_slack "$msg"
exit 0
