#!/bin/bash
# Resolve the --dart-define-from-file JSON for an environment.
#
# CLI: dart_defines.sh <app-root> <env> [configured-path]
# Prints the absolute path of the JSON file to use, or nothing when the
# environment has no dart defines.
#
# Order:
#   1. <configured-path> committed in the repo (environments.<env>.dart_define_file)
#   2. DART_DEFINES_<ENV>_JSON (GitHub secret) or DART_DEFINES_<ENV>_JSON_BASE64
#      (Xcode Cloud secret), written to a private temp file
#   3. nothing (warning)

_DART_DEFINES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common/util.sh
source "$_DART_DEFINES_DIR/util.sh"

resolve_dart_defines() {
  local root="$1" env="$2" configured="${3:-}"
  local upper var json out
  upper="$(printf '%s' "$env" | tr '[:lower:]' '[:upper:]')"
  var="DART_DEFINES_${upper}_JSON"

  if [[ -n "$configured" && -f "$root/$configured" ]]; then
    if ! yq -p json -oy e 'true' "$root/$configured" >/dev/null 2>&1; then
      log_error "$configured is not valid JSON." "CONFIG_REFERENCE.md#dart-defines"
      return 1
    fi
    (cd "$root" && printf '%s/%s' "$(pwd)" "$configured")
    return 0
  fi

  json="$(secret_from_env "$var")"
  if [[ -n "$json" ]]; then
    if ! printf '%s' "$json" | yq -p json -oy e 'true' - >/dev/null 2>&1; then
      log_error "$var (or ${var}_BASE64) is not valid JSON." "SECRETS.md#dart-defines"
      return 1
    fi
    out="$(ci_temp_dir)/dart_defines.$env.json"
    printf '%s' "$json" | write_secret_file "$out"
    log_info "Using dart defines from the $var secret."
    printf '%s' "$out"
    return 0
  fi

  if [[ -n "$configured" ]]; then
    log_error "Dart define file '$configured' (environments.$env.dart_define_file) is not in the repo and no $var / ${var}_BASE64 secret is set." \
      "CONFIG_REFERENCE.md#dart-defines"
    return 1
  fi
  log_warn "No dart defines for '$env' (no dart_define_file and no $var secret)."
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  [[ $# -ge 2 ]] || { echo "usage: dart_defines.sh <app-root> <env> [configured-path]" >&2; exit 2; }
  resolve_dart_defines "$1" "$2" "${3:-}" || exit 1
fi
