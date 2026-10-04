#!/bin/bash
# Create a DRAFT release on the Play production track for a version code that
# was already uploaded (to internal testing) in this run. Nothing reaches
# users until someone opens Play Console and presses "Release".
#
# Env: PLAY_SERVICE_ACCOUNT_JSON, PACKAGE_NAME, VERSION_CODE, RELEASE_NAME
set -euo pipefail

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common/google_auth.sh
source "$_DIR/../common/google_auth.sh"

API="https://androidpublisher.googleapis.com/androidpublisher/v3/applications"

: "${PLAY_SERVICE_ACCOUNT_JSON:?}" "${PACKAGE_NAME:?}" "${VERSION_CODE:?}" "${RELEASE_NAME:?}"

tmp="$(ci_temp_dir)"
sa="$tmp/play-sa.json"
printf '%s' "$PLAY_SERVICE_ACCOUNT_JSON" | write_secret_file "$sa"
token="$(google_access_token "$sa" https://www.googleapis.com/auth/androidpublisher)" || { rm -f "$sa"; exit 1; }
rm -f "$sa"

body="$tmp/play-body.json"

# play_call <method> <url> [json] — prints HTTP status, response in $body.
play_call() {
  local method="$1" url="$2" data="${3:-}"
  local args=(-sS -o "$body" -w '%{http_code}' -X "$method" -H "Authorization: Bearer $token")
  if [[ -n "$data" ]]; then
    args+=(-H 'Content-Type: application/json' --data "$data")
  else
    args+=(-H 'Content-Length: 0')
  fi
  curl "${args[@]}" "$url" || echo 000
}

fail() {
  log_error "Play production draft: $1 (HTTP $2): $(yq -p json -oy e '.error.message // "see log"' "$body" 2>/dev/null)" \
    "TROUBLESHOOTING.md#play-production-draft-fails"
  exit 1
}

log_info "Creating a draft production release '$RELEASE_NAME' (versionCode $VERSION_CODE)..."
code="$(play_call POST "$API/$PACKAGE_NAME/edits")"
[[ "$code" == 200 ]] || fail "could not open an edit" "$code"
edit_id="$(yq -p json -oy e '.id' "$body")"

release="$(NAME="$RELEASE_NAME" VC="$VERSION_CODE" yq -n -o json -I 0 \
  '.track = "production" | .releases = [{"name": strenv(NAME), "versionCodes": [strenv(VC)], "status": "draft"}]')"
code="$(play_call PUT "$API/$PACKAGE_NAME/edits/$edit_id/tracks/production" "$release")"
[[ "$code" == 200 ]] || fail "could not add the build to the production track" "$code"

code="$(play_call POST "$API/$PACKAGE_NAME/edits/$edit_id:commit")"
if [[ "$code" != 200 ]] && grep -q 'changesNotSentForReview' "$body" 2>/dev/null; then
  # Apps with managed publishing / pending changes need this flag.
  code="$(play_call POST "$API/$PACKAGE_NAME/edits/$edit_id:commit?changesNotSentForReview=true")"
fi
[[ "$code" == 200 ]] || fail "could not commit the edit" "$code"
rm -f "$body"
log_info "Draft production release created. Review and release it in Play Console → Production."
