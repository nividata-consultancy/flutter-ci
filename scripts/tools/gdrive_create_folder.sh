#!/bin/bash
# One-time helper (run on your Mac, not in CI): create the Google Drive folder
# that CI uploads into, using the same OAuth client + refresh token as CI.
#
# With the limited `drive.file` scope, CI can only use folders it created
# itself, so the folder must be created through this script, not by hand.
#
# Usage:
#   scripts/tools/gdrive_create_folder.sh "MathRiddle UAT"
#   scripts/tools/gdrive_create_folder.sh "MathRiddle UAT" <parent-folder-id>
#
# Reads GDRIVE_OAUTH_CLIENT_ID / GDRIVE_OAUTH_CLIENT_SECRET /
# GDRIVE_OAUTH_REFRESH_TOKEN from the environment, or asks for them (hidden).
# Prints the folder_id to put in .ci/config.yaml.
set -euo pipefail

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common/google_auth.sh
source "$_DIR/../common/google_auth.sh"
# shellcheck source=scripts/common/read_config.sh
source "$_DIR/../common/read_config.sh"   # ensure_yq

name="${1:-}"
parent="${2:-}"
[[ -n "$name" ]] || { echo "usage: gdrive_create_folder.sh <folder-name> [parent-folder-id]" >&2; exit 2; }
ensure_yq

# ask <VAR> <label> <hidden:true|false> — prompt unless already set; trims spaces/newlines.
ask() {
  local var="$1" label="$2" hidden="$3" value
  if [[ -z "${!var:-}" ]]; then
    printf '%s: ' "$label" >&2
    if [[ "$hidden" == "true" ]]; then
      IFS= read -rs value
      printf '\n' >&2
    else
      IFS= read -r value
    fi
    printf -v "$var" '%s' "$value"
  fi
  value="$(printf '%s' "${!var}" | tr -d ' \t\r\n')"
  printf -v "$var" '%s' "$value"
}
ask GDRIVE_OAUTH_CLIENT_ID "OAuth client ID (shown; ends with .apps.googleusercontent.com)" false
if [[ "$GDRIVE_OAUTH_CLIENT_ID" != *.apps.googleusercontent.com ]]; then
  die "That is not an OAuth client ID: it must end with .apps.googleusercontent.com. Copy it from Google Cloud → APIs & Services → Credentials → OAuth 2.0 Client IDs." \
    "ANDROID_SETUP.md#option-2-your-own-google-account"
fi
ask GDRIVE_OAUTH_CLIENT_SECRET "OAuth client secret (hidden)" true
ask GDRIVE_OAUTH_REFRESH_TOKEN "Refresh token (hidden)" true

token="$(google_access_token_from_refresh "$GDRIVE_OAUTH_CLIENT_ID" "$GDRIVE_OAUTH_CLIENT_SECRET" "$GDRIVE_OAUTH_REFRESH_TOKEN")"

meta="$(NAME="$name" PARENT="$parent" yq -n -o json -I 0 \
  '.name = strenv(NAME) | .mimeType = "application/vnd.google-apps.folder" | (select(strenv(PARENT) != "") | .parents) = [strenv(PARENT)]')"
resp="$(curl -sS -X POST "https://www.googleapis.com/drive/v3/files?fields=id,webViewLink&supportsAllDrives=true" \
  -H "Authorization: Bearer $token" -H 'Content-Type: application/json; charset=UTF-8' --data "$meta")"
id="$(printf '%s' "$resp" | yq -p json -oy e '.id // ""' -)"
if [[ -z "$id" ]]; then
  die "Could not create the folder: $(printf '%s' "$resp" | yq -p json -oy e '.error.message // "unknown error"' -)" \
    "ANDROID_SETUP.md#option-2-your-own-google-account"
fi

cat <<OUT

Created folder "$name"
  Open:      $(printf '%s' "$resp" | yq -p json -oy e '.webViewLink' -)
  folder_id: $id

Put it in .ci/config.yaml:
  drive: { enabled: true, folder_id: "$id" }

To let your team see the builds, open the link above and use Share.
OUT
