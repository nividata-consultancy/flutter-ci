#!/bin/bash
# Resolve everything a build needs from the tag + .ci/config.yaml + the app's
# pinned Flutter version. Shared by GitHub Actions and Xcode Cloud so both
# platforms read the config the same way.
#
# CLI: context.sh <app-root> <config-path> <tag> <android|ios>
#   - validates the config (fails fast with readable errors)
#   - prints KEY=VALUE lines (shell-quoted, safe to `source`)
#   - on GitHub also writes every key to $GITHUB_OUTPUT
#
# Paths in the output (DART_DEFINE_FILE, IOS_GOOGLE_SERVICE_INFO) are relative
# to <app-root>. <config-path> is relative to <app-root> unless absolute.

_CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common/parse_tag.sh
source "$_CONTEXT_DIR/parse_tag.sh"
# shellcheck source=scripts/common/read_config.sh
source "$_CONTEXT_DIR/read_config.sh"
# shellcheck source=scripts/common/flutter_version.sh
source "$_CONTEXT_DIR/flutter_version.sh"

_CTX_KEYS=()

_ctx() {
  local key="$1" value="$2"
  printf -v "$key" '%s' "$value"
  export "${key?}"
  _CTX_KEYS+=("$key")
}

_ctx_destinations() {
  local base="$1"
  if cfg_has "$base.firebase"; then
    _ctx FIREBASE_ENABLED true
    _ctx FIREBASE_GROUPS "$(cfg "$base.firebase.groups")"
    _ctx FIREBASE_TESTERS "$(cfg "$base.firebase.testers")"
  else
    _ctx FIREBASE_ENABLED false
    _ctx FIREBASE_GROUPS ""
    _ctx FIREBASE_TESTERS ""
  fi
  if cfg_has "$base.drive"; then
    _ctx DRIVE_ENABLED true
    _ctx DRIVE_FOLDER_ID "$(cfg "$base.drive.folder_id")"
  else
    _ctx DRIVE_ENABLED false
    _ctx DRIVE_FOLDER_ID ""
  fi
}

# resolve_context <app-root> <config-path> <tag> <android|ios>
resolve_context() {
  local root="$1" config="$2" tag="$3" platform="$4"
  _CTX_KEYS=()

  case "$platform" in
    android | ios) ;;
    *) log_error "platform must be android or ios (got '$platform')"; return 1 ;;
  esac

  parse_tag "$tag" || return 1
  [[ "$config" == /* ]] || config="$root/$config"
  ensure_yq
  validate_config "$config" "$ENVIRONMENT" || return 1

  local env="$ENVIRONMENT" e=".environments.$ENVIRONMENT"
  _ctx TAG "$TAG"
  _ctx ENVIRONMENT "$env"
  _ctx ENV_LABEL "$(printf '%s' "$env" | tr '[:lower:]' '[:upper:]')"
  _ctx VERSION_NAME "$VERSION_NAME"
  _ctx VERSION_NAME_FULL "$VERSION_NAME_FULL"
  _ctx IS_PRERELEASE "$IS_PRERELEASE"
  _ctx APP_NAME "$(cfg '.app.name')"

  detect_flutter_version "$root" "$(cfg '.app.flutter_version_file')" || return 1
  _ctx FLUTTER_VERSION "$FLUTTER_VERSION"
  _ctx FLUTTER_CHANNEL "$FLUTTER_CHANNEL"

  local branches
  branches="$(cfg_list '.app.prod_branches' | tr '\n' ' ' | sed 's/ *$//')"
  # Empty = prod tags may be on any branch (no prod guard).
  _ctx PROD_BRANCHES "$branches"
  _ctx RUN_TESTS "$(cfg '.app.run_tests' true)"
  _ctx RUN_ANALYZE "$(cfg '.app.run_analyze' false)"
  _ctx OBFUSCATE "$(cfg '.app.obfuscate' false)"
  _ctx DART_DEFINE_FILE "$(cfg "$e.dart_define_file")"

  if [[ "$platform" == "android" ]]; then
    local a="$e.android"
    _ctx JAVA_VERSION "$(cfg '.app.java_version' 17)"
    _ctx BUILD_NUMBER_OFFSET "$(cfg '.app.build_number_offset' 0)"
    _ctx ANDROID_PACKAGE_NAME "$(cfg '.app.android_package_name')"
    _ctx ANDROID_FLAVOR "$(cfg "$a.flavor")"
    _ctx ANDROID_TARGET "$(cfg "$a.target")"
    local artifacts
    artifacts="$(cfg_list "$a.artifacts" | tr '\n' ' ' | sed 's/ *$//')"
    _ctx ANDROID_ARTIFACTS "${artifacts:-aab}"
    if cfg_has "$a.destinations.playstore"; then
      _ctx PLAYSTORE_ENABLED true
    else
      _ctx PLAYSTORE_ENABLED false
    fi
    _ctx PLAYSTORE_TRACK "$(cfg "$a.destinations.playstore.track" internal)"
    _ctx PLAYSTORE_STATUS "$(cfg "$a.destinations.playstore.status" completed)"
    _ctx PLAYSTORE_PRODUCTION "$(cfg "$a.destinations.playstore.production" false)"
    _ctx_destinations "$a.destinations"
    _ctx GITHUB_RELEASE "$(cfg '.app.github_release.enabled' true)"
    _ctx GITHUB_RELEASE_ATTACH "$(cfg '.app.github_release.attach_artifacts' false)"
  else
    local i="$e.ios"
    _ctx IOS_DISPLAY_NAME "$(cfg "$i.display_name")"
    _ctx IOS_APP_ICON "$(cfg "$i.app_icon")"
    _ctx IOS_GOOGLE_SERVICE_INFO "$(cfg "$i.google_service_info")"
    _ctx IOS_TARGET "$(cfg "$i.target")"
  fi
}

# print_context — KEY='value' lines, safe to source.
print_context() {
  local k
  for k in "${_CTX_KEYS[@]}"; do
    printf '%s=%q\n' "$k" "${!k}"
  done
}

# context_to_github_output — write every key to $GITHUB_OUTPUT (if set).
context_to_github_output() {
  local k
  for k in "${_CTX_KEYS[@]}"; do
    set_output "$k" "${!k}"
  done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  [[ $# -eq 4 ]] || { echo "usage: context.sh <app-root> <config-path> <tag> <android|ios>" >&2; exit 2; }
  resolve_context "$@" || exit 1
  context_to_github_output
  print_context
fi
