#!/bin/bash
# Upload an APK / AAB / IPA to Firebase App Distribution.
#
# CLI: firebase_distribute.sh --file <path> --app <firebase-app-id>
#        [--groups "a,b"] [--testers "x@y.z"] [--release-notes-file <path>]
#
# Credentials: FIREBASE_SERVICE_ACCOUNT_JSON (raw JSON, GitHub) or
# FIREBASE_SERVICE_ACCOUNT_JSON_BASE64 (Xcode Cloud).
# The Firebase CLI standalone binary is downloaded if `firebase` is missing.
# Pin it with FIREBASE_TOOLS_VERSION (e.g. 14.20.0); default: latest.
#
# Prints the Firebase console link of the release on success.

_FIREBASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common/util.sh
source "$_FIREBASE_DIR/util.sh"

ensure_firebase_cli() {
  if command -v firebase >/dev/null 2>&1; then
    command -v firebase
    return 0
  fi
  local os bin version url
  case "$(uname -s)" in
    Darwin) os=macos ;;
    Linux) os=linux ;;
    *) log_error "Unsupported OS for the Firebase CLI: $(uname -s)"; return 1 ;;
  esac
  bin="$(tools_dir)/firebase"
  if [[ ! -x "$bin" ]]; then
    version="${FIREBASE_TOOLS_VERSION:-latest}"
    [[ "$version" == latest ]] || version="v${version#v}"
    url="https://firebase.tools/bin/$os/$version"
    log_info "Downloading Firebase CLI ($version) from $url"
    curl -fsSL --retry 3 -o "$bin.tmp" "$url" || { log_error "Could not download the Firebase CLI from $url"; return 1; }
    chmod +x "$bin.tmp"
    mv "$bin.tmp" "$bin"
  fi
  printf '%s' "$bin"
}

firebase_distribute() {
  local file="" app="" groups="" testers="" notes=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file) file="$2"; shift 2 ;;
      --app) app="$2"; shift 2 ;;
      --groups) groups="$2"; shift 2 ;;
      --testers) testers="$2"; shift 2 ;;
      --release-notes-file) notes="$2"; shift 2 ;;
      *) log_error "firebase_distribute: unknown argument $1"; return 2 ;;
    esac
  done

  [[ -f "$file" ]] || { log_error "Firebase: file to upload not found: $file"; return 1; }
  [[ -n "$app" ]] || { log_error "Firebase: the Firebase app ID is not set (FIREBASE_ANDROID_APP_ID secret)." "SECRETS.md#firebase-app-distribution"; return 1; }

  local creds_json
  creds_json="$(secret_from_env FIREBASE_SERVICE_ACCOUNT_JSON)"
  [[ -n "$creds_json" ]] || { log_error "Firebase: FIREBASE_SERVICE_ACCOUNT_JSON (or _BASE64) is not set." "SECRETS.md#firebase-app-distribution"; return 1; }

  local cli tmp creds
  cli="$(ensure_firebase_cli)" || return 1
  tmp="$(ci_temp_dir)"
  creds="$tmp/firebase-sa.json"
  printf '%s' "$creds_json" | write_secret_file "$creds"

  local args=(appdistribution:distribute "$file" --app "$app" --non-interactive)
  [[ -n "$groups" ]] && args+=(--groups "$groups")
  [[ -n "$testers" ]] && args+=(--testers "$testers")
  [[ -n "$notes" && -f "$notes" ]] && args+=(--release-notes-file "$notes")

  log_info "Uploading $(basename "$file") to Firebase App Distribution${groups:+ (groups: $groups)}..."
  local out rc=0
  out="$(GOOGLE_APPLICATION_CREDENTIALS="$creds" "$cli" "${args[@]}" 2>&1)" || rc=$?
  rm -f "$creds"
  printf '%s\n' "$out" >&2
  if [[ $rc -ne 0 ]]; then
    log_error "Firebase App Distribution upload failed (exit $rc). Check the service account has the 'Firebase App Distribution Admin' role and the app ID is right." \
      "TROUBLESHOOTING.md#firebase-upload-fails"
    return 1
  fi
  printf '%s\n' "$out" | grep -Eo 'https://console\.firebase\.google\.com[^ ]*' | head -n 1 || true
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  firebase_distribute "$@" || exit 1
fi
