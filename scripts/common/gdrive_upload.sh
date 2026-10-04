#!/bin/bash
# Upload a file to a folder in a Google *Shared Drive* with a service account.
#
# Service accounts have no My Drive storage quota, so the folder MUST live in
# a Shared Drive and the service account must be a member (Content manager).
#
# CLI: gdrive_upload.sh <file> <folder-id> [name]
# Credentials: GDRIVE_SERVICE_ACCOUNT_JSON (raw) or GDRIVE_SERVICE_ACCOUNT_JSON_BASE64.
# Prints the file's webViewLink on success. Needs curl, openssl and yq.

_GDRIVE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common/util.sh
source "$_GDRIVE_DIR/util.sh"

_b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# _gdrive_token <sa-json-file> — print an OAuth access token.
_gdrive_token() {
  local sa="$1" email key_file token_uri now header claims unsigned sig resp token
  email="$(yq -p json -oy e '.client_email // ""' "$sa")"
  token_uri="$(yq -p json -oy e '.token_uri // "https://oauth2.googleapis.com/token"' "$sa")"
  [[ -n "$email" ]] || { log_error "Drive: the service account JSON has no client_email." "SECRETS.md#google-drive"; return 1; }

  key_file="$(ci_temp_dir)/gdrive-key.pem"
  yq -p json -oy e '.private_key' "$sa" | write_secret_file "$key_file"

  now="$(date +%s)"
  header="$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | _b64url)"
  claims="$(EMAIL="$email" AUD="$token_uri" NOW="$now" yq -n -o json -I 0 \
    '.iss = strenv(EMAIL) | .scope = "https://www.googleapis.com/auth/drive" | .aud = strenv(AUD) | .iat = (strenv(NOW) | tonumber) | .exp = ((strenv(NOW) | tonumber) + 3600)' | _b64url)"
  unsigned="$header.$claims"
  sig="$(printf '%s' "$unsigned" | openssl dgst -sha256 -sign "$key_file" | _b64url)" || { rm -f "$key_file"; return 1; }
  rm -f "$key_file"

  resp="$(curl -sS -X POST "$token_uri" \
    --data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer' \
    --data-urlencode "assertion=$unsigned.$sig")" || { log_error "Drive: token request failed."; return 1; }
  token="$(printf '%s' "$resp" | yq -p json -oy e '.access_token // ""' -)"
  if [[ -z "$token" ]]; then
    log_error "Drive: could not get an access token: $(printf '%s' "$resp" | yq -p json -oy e '.error_description // .error // "unknown error"' -)" "SECRETS.md#google-drive"
    return 1
  fi
  mask "$token"
  printf '%s' "$token"
}

gdrive_upload() {
  local file="$1" folder="$2" name="${3:-}"
  [[ -f "$file" ]] || { log_error "Drive: file not found: $file"; return 1; }
  [[ -n "$folder" ]] || { log_error "Drive: folder_id is empty." "CONFIG_REFERENCE.md#destinations"; return 1; }
  [[ -n "$name" ]] || name="$(basename "$file")"

  local sa_json tmp sa token
  sa_json="$(secret_from_env GDRIVE_SERVICE_ACCOUNT_JSON)"
  [[ -n "$sa_json" ]] || { log_error "Drive: GDRIVE_SERVICE_ACCOUNT_JSON (or _BASE64) is not set." "SECRETS.md#google-drive"; return 1; }
  tmp="$(ci_temp_dir)"
  sa="$tmp/gdrive-sa.json"
  printf '%s' "$sa_json" | write_secret_file "$sa"
  token="$(_gdrive_token "$sa")" || { rm -f "$sa"; return 1; }
  rm -f "$sa"

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
      log_error "Drive: storage quota exceeded. The folder is probably in someone's My Drive; service accounts can only upload into a Shared Drive folder." \
        "TROUBLESHOOTING.md#drive-storage-quota-exceeded" ;;
    notFound)
      log_error "Drive: folder not found. Add the service account as a member (Content manager) of the Shared Drive and check folder_id." \
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
