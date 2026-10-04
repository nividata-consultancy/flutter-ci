#!/bin/bash
# Detect the Flutter version an app pins.
#
#   .fvmrc        {"flutter": "3.24.5"}       (FVM 3; "3.24.5@stable" also accepted)
#   pubspec.yaml  environment: { flutter: "3.24.5" }   (must be an exact version)
#
# CLI:  flutter_version.sh <app-root> [.fvmrc|pubspec.yaml]   prints the version
# Lib:  detect_flutter_version <app-root> [file]             sets FLUTTER_VERSION
#
# With no file given, .fvmrc wins over pubspec.yaml.

_FLUTTER_VERSION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common/log.sh
source "$_FLUTTER_VERSION_DIR/log.sh"

FLUTTER_CI_FLUTTER_VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9]+\.[0-9]+\.pre)?$'

_fv_from_fvmrc() {
  # .fvmrc is JSON; yq reads JSON with -p json.
  yq -p json e '.flutter // ""' "$1" 2>/dev/null
}

_fv_from_pubspec() {
  yq e '.environment.flutter // ""' "$1" 2>/dev/null
}

detect_flutter_version() {
  local root="$1" which="${2:-}" raw="" src=""

  if [[ -z "$which" ]]; then
    if [[ -f "$root/.fvmrc" ]]; then
      which=".fvmrc"
    elif [[ -f "$root/pubspec.yaml" && -n "$(_fv_from_pubspec "$root/pubspec.yaml")" ]]; then
      which="pubspec.yaml"
    else
      log_error "Could not find the Flutter version: add .fvmrc ({\"flutter\": \"X.Y.Z\"}) or environment.flutter: \"X.Y.Z\" to pubspec.yaml." \
        "CONFIG_REFERENCE.md#flutter-version"
      return 1
    fi
  fi

  case "$which" in
    .fvmrc)
      [[ -f "$root/.fvmrc" ]] || { log_error "app.flutter_version_file is .fvmrc but $root/.fvmrc does not exist." "CONFIG_REFERENCE.md#flutter-version"; return 1; }
      raw="$(_fv_from_fvmrc "$root/.fvmrc")"
      src=".fvmrc (key 'flutter')"
      ;;
    pubspec.yaml)
      [[ -f "$root/pubspec.yaml" ]] || { log_error "$root/pubspec.yaml does not exist." "CONFIG_REFERENCE.md#flutter-version"; return 1; }
      raw="$(_fv_from_pubspec "$root/pubspec.yaml")"
      src="pubspec.yaml (environment.flutter)"
      ;;
    *)
      log_error "Unsupported Flutter version file '$which' (use .fvmrc or pubspec.yaml)." "CONFIG_REFERENCE.md#flutter-version"
      return 1
      ;;
  esac

  # Strip quotes, whitespace, a leading '=' and an FVM '@channel' suffix.
  raw="${raw//\"/}"
  raw="${raw//\'/}"
  raw="${raw// /}"
  raw="${raw#=}"
  raw="${raw%%@*}"

  if [[ -z "$raw" ]]; then
    log_error "No Flutter version found in $src." "CONFIG_REFERENCE.md#flutter-version"
    return 1
  fi
  if [[ ! "$raw" =~ $FLUTTER_CI_FLUTTER_VERSION_RE ]]; then
    log_error "Flutter version '$raw' from $src must be an exact release like 3.24.5 (no ranges, channels or '^')." \
      "CONFIG_REFERENCE.md#flutter-version"
    return 1
  fi
  FLUTTER_VERSION="$raw"
  # Pre-releases (3.27.0-0.1.pre) live on the beta channel.
  if [[ "$raw" == *.pre ]]; then FLUTTER_CHANNEL="beta"; else FLUTTER_CHANNEL="stable"; fi
  export FLUTTER_VERSION FLUTTER_CHANNEL
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  [[ $# -ge 1 ]] || { echo "usage: flutter_version.sh <app-root> [.fvmrc|pubspec.yaml]" >&2; exit 2; }
  detect_flutter_version "$1" "${2:-}" || exit 1
  printf '%s\n' "$FLUTTER_VERSION"
fi
