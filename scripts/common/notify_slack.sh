#!/bin/bash
# Post a message to Slack through an incoming webhook (SLACK_WEBHOOK_URL).
# Never fails: a broken notification must not fail a build.
#
# CLI: notify_slack.sh <message>

_SLACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common/log.sh
source "$_SLACK_DIR/log.sh"

notify_slack() {
  local text="$1" url="${SLACK_WEBHOOK_URL:-}" payload
  if [[ -z "$url" ]]; then
    log_info "Slack: SLACK_WEBHOOK_URL not set; skipping notification."
    return 0
  fi
  if ! payload="$(TEXT="$text" yq -n -o json -I 0 '.text = strenv(TEXT)' 2>/dev/null)"; then
    log_warn "Slack: could not build the payload; skipping."
    return 0
  fi
  if curl -fsS --max-time 15 -X POST -H 'Content-Type: application/json' --data "$payload" "$url" >/dev/null 2>&1; then
    log_info "Slack: notification sent."
  else
    log_warn "Slack: notification failed (ignored)."
  fi
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -uo pipefail
  notify_slack "${1:-}"
  exit 0
fi
