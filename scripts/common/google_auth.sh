#!/bin/bash
# Google service account → OAuth access token (JWT bearer flow), using only
# curl, openssl and yq. Shared by the Drive upload and the Play API calls.
#
# Lib: google_access_token <service-account.json> <scope>   prints the token
#      google_access_token_from_refresh <client-id> <client-secret> <refresh-token>
#        (a real user's OAuth token: uploads use that user's own Drive storage)

_GOOGLE_AUTH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common/util.sh
source "$_GOOGLE_AUTH_DIR/util.sh"

_b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

google_access_token() {
  local sa="$1" scope="$2" email key_file token_uri now header claims unsigned sig resp token
  email="$(yq -p json -oy e '.client_email // ""' "$sa")"
  token_uri="$(yq -p json -oy e '.token_uri // "https://oauth2.googleapis.com/token"' "$sa")"
  [[ -n "$email" ]] || { log_error "The service account JSON has no client_email." "ANDROID_SETUP.md"; return 1; }

  key_file="$(ci_temp_dir)/google-key.pem"
  yq -p json -oy e '.private_key' "$sa" | write_secret_file "$key_file"

  now="$(date +%s)"
  header="$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | _b64url)"
  claims="$(EMAIL="$email" AUD="$token_uri" NOW="$now" SCOPE="$scope" yq -n -o json -I 0 \
    '.iss = strenv(EMAIL) | .scope = strenv(SCOPE) | .aud = strenv(AUD) | .iat = (strenv(NOW) | tonumber) | .exp = ((strenv(NOW) | tonumber) + 3600)' | _b64url)"
  unsigned="$header.$claims"
  sig="$(printf '%s' "$unsigned" | openssl dgst -sha256 -sign "$key_file" | _b64url)" || { rm -f "$key_file"; return 1; }
  rm -f "$key_file"

  resp="$(curl -sS -X POST "$token_uri" \
    --data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer' \
    --data-urlencode "assertion=$unsigned.$sig")" || { log_error "Google token request failed."; return 1; }
  token="$(printf '%s' "$resp" | yq -p json -oy e '.access_token // ""' -)"
  if [[ -z "$token" ]]; then
    log_error "Could not get a Google access token: $(printf '%s' "$resp" | yq -p json -oy e '.error_description // .error // "unknown error"' -)" "ANDROID_SETUP.md"
    return 1
  fi
  mask "$token"
  printf '%s' "$token"
}

google_access_token_from_refresh() {
  local client_id="$1" client_secret="$2" refresh_token="$3" resp token
  resp="$(curl -sS -X POST https://oauth2.googleapis.com/token \
    --data-urlencode "client_id=$client_id" \
    --data-urlencode "client_secret=$client_secret" \
    --data-urlencode "refresh_token=$refresh_token" \
    --data-urlencode 'grant_type=refresh_token')" || { log_error "Google token request failed."; return 1; }
  token="$(printf '%s' "$resp" | yq -p json -oy e '.access_token // ""' -)"
  if [[ -z "$token" ]]; then
    log_error "Could not get a Google access token from the refresh token: $(printf '%s' "$resp" | yq -p json -oy e '.error_description // .error // "unknown error"' -). If it says 'invalid_grant', create a new refresh token." \
      "ANDROID_SETUP.md#option-2-your-own-google-account"
    return 1
  fi
  mask "$token"
  printf '%s' "$token"
}
