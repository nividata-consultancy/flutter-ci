#!/bin/bash
# Upload a file to a Google Drive folder.
#
# Credentials, first match wins:
#   A. GDRIVE_OAUTH_CLIENT_ID + GDRIVE_OAUTH_CLIENT_SECRET + GDRIVE_OAUTH_REFRESH_TOKEN
#      Uploads as a real Google user into their own My Drive (their storage).
#      Works with personal Gmail accounts.
#   B. GDRIVE_SERVICE_ACCOUNT_JSON (raw) or GDRIVE_SERVICE_ACCOUNT_JSON_BASE64
#      A service account has no storage of its own, so the folder MUST be in a
#      Shared Drive where the service account is a member (Content manager).
#
# CLI: gdrive_upload.sh <file> <folder-id> [name]
# Prints the file's webViewLink on success. Needs curl, openssl and yq.

_GDRIVE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common/google_auth.sh
source "$_GDRIVE_DIR/google_auth.sh"

gdrive_upload() {
  local file="$1" folder="$2" name="${3:-}"
  [[ -f "$file" ]] || { log_error "Drive: file not found: $file"; return 1; }
  [[ -n "$folder" ]] || { log_error "Drive: folder_id is empty." "CONFIG_REFERENCE.md#destinations"; return 1; }
  [[ -n "$name" ]] || name="$(basename "$file")"

  local sa_json tmp sa token
  tmp="$(ci_temp_dir)"
  if [[ -n "${GDRIVE_OAUTH_REFRESH_TOKEN:-}" ]]; then
    [[ -n "${GDRIVE_OAUTH_CLIENT_ID:-}" && -n "${GDRIVE_OAUTH_CLIENT_SECRET:-}" ]] \
      || { log_error "Drive: GDRIVE_OAUTH_REFRESH_TOKEN is set, but GDRIVE_OAUTH_CLIENT_ID / GDRIVE_OAUTH_CLIENT_SECRET are missing." "SECRETS.md#option-b-your-own-google-account-my-drive"; return 1; }
    log_info "Drive: uploading as your Google account (OAuth refresh token)."
    token="$(google_access_token_from_refresh "$GDRIVE_OAUTH_CLIENT_ID" "$GDRIVE_OAUTH_CLIENT_SECRET" "$GDRIVE_OAUTH_REFRESH_TOKEN")" || return 1
  else
    sa_json="$(secret_from_env GDRIVE_SERVICE_ACCOUNT_JSON)"
    [[ -n "$sa_json" ]] || { log_error "Drive: no credentials. Set GDRIVE_OAUTH_CLIENT_ID + GDRIVE_OAUTH_CLIENT_SECRET + GDRIVE_OAUTH_REFRESH_TOKEN (your own account), or GDRIVE_SERVICE_ACCOUNT_JSON (Shared Drive)." "SECRETS.md#google-drive"; return 1; }
    sa="$tmp/gdrive-sa.json"
    printf '%s' "$sa_json" | write_secret_file "$sa"
    token="$(google_access_token "$sa" https://www.googleapis.com/auth/drive)" || { rm -f "$sa"; return 1; }
    rm -f "$sa"
  fi

  local meta headers body code location
  meta="$(NAME="$name" FOLDER="$folder" yq -n -o json -I 0 '.name = strenv(NAME) | .parents = [strenv(FOLDER)]')"
  headers="$tmp/gdrive-headers.txt"
  body="$tmp/gdrive-body.json"

  log_info "Uploading $name to Google Drive folder $folder..."
  code="$(curl -sS -o "$body" -D "$headers" -w '%{http_code}' -X POST \
    "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&supportsAllDrives=true&fields=id,name,webViewLink" \
    -H "Authorization: Bearer $token" \
    -H 'Content-Type: application/json; charset=UTF-8' \
    -H 'X-Upload-Content-Type: application/octet-stream' \
    --data "$meta")" || code=000
  if [[ "$code" != 200 ]]; then
    _gdrive_fail "$code" "$body"
    return 1
  fi
  location="$(grep -i '^location:' "$headers" | head -n 1 | cut -d' ' -f2- | tr -d '\r')"

  code="$(curl -sS -o "$body" -w '%{http_code}' -X PUT "$location" \
    -H 'Content-Type: application/octet-stream' --upload-file "$file")" || code=000
  if [[ "$code" != 200 && "$code" != 201 ]]; then
    _gdrive_fail "$code" "$body"
    return 1
  fi
  yq -p json -oy e '.webViewLink // ""' "$body"
  rm -f "$headers" "$body"
}

_gdrive_fail() {
  local code="$1" body="$2" reason msg
  reason="$(yq -p json -oy e '.error.errors[0].reason // ""' "$body" 2>/dev/null || true)"
  msg="$(yq -p json -oy e '.error.message // ""' "$body" 2>/dev/null || true)"
  case "$reason" in
    storageQuotaExceeded)
      log_error "Drive: storage quota exceeded. With a service account the folder must be in a Shared Drive; with your own account (OAuth), your Drive is full." \
        "TROUBLESHOOTING.md#drive-storage-quota-exceeded" ;;
    notFound)
      log_error "Drive: folder not found. Check folder_id, and that the account used for uploads can edit that folder." \
        "SECRETS.md#google-drive" ;;
    *)
      log_error "Drive: upload failed (HTTP $code${reason:+, $reason}): ${msg:-see log}" "TROUBLESHOOTING.md#drive-storage-quota-exceeded" ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  [[ $# -ge 2 ]] || { echo "usage: gdrive_upload.sh <file> <folder-id> [name]" >&2; exit 2; }
  gdrive_upload "$@" || exit 1
fi
