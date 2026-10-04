#!/bin/bash
# Read and validate the per-project config (.ci/config.yaml, schema version 1).
# The schema is documented in docs/CONFIG_REFERENCE.md — keep them in sync.
#
# CLI:
#   read_config.sh validate <config.yaml> [env]   exit 1 with readable errors
#   read_config.sh get <config.yaml> <yq-path>     print a value ("" if unset)
#
# Library (after `source`):
#   ensure_yq
#   config_load <config.yaml>         sets FLUTTER_CI_CONFIG
#   cfg <yq-path> [default]           scalar value or default
#   cfg_list <yq-path>                one item per line
#   cfg_has <yq-path>                 0 if the path exists and is not null
#   validate_config <config.yaml> [env]

_READ_CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common/log.sh
source "$_READ_CONFIG_DIR/log.sh"

FLUTTER_CI_SCHEMA_VERSION=1

# ensure_yq — make sure mikefarah/yq v4 is on PATH. Installs it with Homebrew
# when missing (Xcode Cloud); ubuntu-latest runners ship it preinstalled.
ensure_yq() {
  if command -v yq >/dev/null 2>&1 && yq --version 2>&1 | grep -q 'mikefarah'; then
    return 0
  fi
  if command -v yq >/dev/null 2>&1; then
    log_warn "The 'yq' on PATH is not mikefarah/yq v4; trying to install the right one."
  fi
  if command -v brew >/dev/null 2>&1; then
    log_info "Installing yq with Homebrew..."
    HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install yq >&2 \
      || die "Could not install yq with Homebrew." "TROUBLESHOOTING.md#yq-missing"
    return 0
  fi
  die "mikefarah/yq v4 is required but was not found on PATH." "TROUBLESHOOTING.md#yq-missing"
}

config_load() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    die "Config file '$file' not found. Copy templates/.ci/config.yaml into your app repo." \
      "NEW_PROJECT_SETUP.md#2-fill-in-ciconfigyaml"
  fi
  if ! yq e 'true' "$file" >/dev/null 2>&1; then
    die "Config file '$file' is not valid YAML: $(yq e 'true' "$file" 2>&1 | head -n 3)" \
      "CONFIG_REFERENCE.md"
  fi
  FLUTTER_CI_CONFIG="$file"
  export FLUTTER_CI_CONFIG
}

# cfg <path> [default] — print the scalar at <path>; <default> when null/missing.
# Unlike yq's `//`, a literal `false` is returned as "false".
cfg() {
  local path="$1" default="${2:-}" v
  v="$(yq e "($path) | select(. != null)" "$FLUTTER_CI_CONFIG")"
  if [[ -z "$v" ]]; then v="$default"; fi
  printf '%s' "$v"
}

cfg_list() {
  yq e "($1) // [] | .[]" "$FLUTTER_CI_CONFIG"
}

cfg_has() {
  [[ "$(yq e "($1) != null" "$FLUTTER_CI_CONFIG")" == "true" ]]
}

# ---------------------------------------------------------------- validation

_cfg_type() { yq e "($1) | type" "$FLUTTER_CI_CONFIG"; }

_cfg_err() { _CFG_ERRORS+=("$1"); }

# _cfg_expect_type <path> <label> <allowed !!types...>  (missing/null is allowed)
_cfg_expect_type() {
  local path="$1" label="$2" t
  shift 2
  t="$(_cfg_type "$path")"
  [[ "$t" == "!!null" ]] && return 1
  local want
  for want in "$@"; do
    [[ "$t" == "$want" ]] && return 0
  done
  _cfg_err "$label must be $(_cfg_type_names "$@") (got ${t#!!})"
  return 1
}

_cfg_type_names() {
  local out="" t
  for t in "$@"; do
    case "$t" in
      '!!str') t="a string" ;; '!!int') t="an integer" ;; '!!bool') t="true/false" ;;
      '!!seq') t="a list" ;; '!!map') t="a mapping" ;;
    esac
    if [[ -z "$out" ]]; then out="$t"; else out="$out or $t"; fi
  done
  printf '%s' "$out"
}

# _cfg_known_keys <path> <label> <allowed keys...> — reject typos early.
_cfg_known_keys() {
  local path="$1" label="$2" key ok allowed
  shift 2
  [[ "$(_cfg_type "$path")" == "!!map" ]] || return 0
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    ok=0
    for allowed in "$@"; do
      if [[ "$key" == "$allowed" ]]; then ok=1; break; fi
    done
    if [[ $ok -eq 0 ]]; then
      _cfg_err "$label: unknown key '$key' (allowed: $*)"
    fi
  done < <(yq e "($path) | keys | .[]" "$FLUTTER_CI_CONFIG")
}

_cfg_validate_folder_id() {
  local path="$1" label="$2" v
  if ! cfg_has "$path"; then
    _cfg_err "$label is required"
    return
  fi
  _cfg_expect_type "$path" "$label" '!!str' || return
  v="$(cfg "$path")"
  if [[ "$v" == "SHARED_DRIVE_FOLDER_ID" || ! "$v" =~ ^[A-Za-z0-9_-]+$ ]]; then
    _cfg_err "$label must be a Google Drive folder ID, the part after /folders/ in the folder's URL (got '$v')"
  fi
}

_cfg_validate_android() {
  local env="$1" p=".environments.$1.android" label="environments.$1.android"
  _cfg_expect_type "$p" "$label" '!!map' || return 0
  _cfg_known_keys "$p" "$label" flavor target artifacts destinations

  if _cfg_expect_type "$p.flavor" "$label.flavor" '!!str'; then
    [[ "$(cfg "$p.flavor")" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] \
      || _cfg_err "$label.flavor must be a Gradle flavor name like 'uat' (letters, digits, _)"
  fi
  if _cfg_expect_type "$p.target" "$label.target" '!!str'; then
    [[ "$(cfg "$p.target")" == *.dart ]] || _cfg_err "$label.target must point to a .dart file"
  fi

  local has_aab=1 has_apk=0
  if _cfg_expect_type "$p.artifacts" "$label.artifacts" '!!seq'; then
    has_aab=0
    local a n=0
    while IFS= read -r a; do
      n=$((n + 1))
      case "$a" in
        aab) has_aab=1 ;;
        apk) has_apk=1 ;;
        *) _cfg_err "$label.artifacts: '$a' is not supported (use aab and/or apk)" ;;
      esac
    done < <(cfg_list "$p.artifacts")
    [[ $n -gt 0 ]] || _cfg_err "$label.artifacts must list at least one of: aab, apk"
  fi

  local d="$p.destinations" dl="$label.destinations"
  _cfg_expect_type "$d" "$dl" '!!map' || return 0
  _cfg_known_keys "$d" "$dl" playstore firebase drive

  # Every destination needs an explicit `enabled: true|false`. Disabled
  # destinations keep their settings but are neither checked nor used.
  if cfg_has "$d.playstore" && _cfg_expect_type "$d.playstore" "$dl.playstore" '!!map'; then
    _cfg_known_keys "$d.playstore" "$dl.playstore" enabled tracks status
    if _cfg_dest_enabled "$d.playstore" "$dl.playstore"; then
      if ! cfg_has "$d.playstore.tracks"; then
        _cfg_err "$dl.playstore.tracks is required, e.g. [internal], [production] or [internal, production]"
      elif _cfg_expect_type "$d.playstore.tracks" "$dl.playstore.tracks" '!!seq'; then
        local t n_testing=0 n_total=0
        while IFS= read -r t; do
          n_total=$((n_total + 1))
          if [[ "$t" == "production" ]]; then
            [[ "$env" == "prod" ]] || _cfg_err "$dl.playstore.tracks: 'production' is only allowed in the prod environment"
          elif [[ "$t" =~ ^[A-Za-z0-9_:-]+$ ]]; then
            n_testing=$((n_testing + 1))
          else
            _cfg_err "$dl.playstore.tracks: '$t' is not a valid track name"
          fi
        done < <(cfg_list "$d.playstore.tracks")
        [[ $n_total -gt 0 ]] || _cfg_err "$dl.playstore.tracks must list at least one track"
        [[ $n_testing -le 1 ]] || _cfg_err "$dl.playstore.tracks: list at most one testing track (e.g. internal), optionally plus production"
      fi
      if _cfg_expect_type "$d.playstore.status" "$dl.playstore.status" '!!str'; then
        case "$(cfg "$d.playstore.status")" in
          completed | draft) ;;
          *) _cfg_err "$dl.playstore.status must be 'completed' or 'draft'" ;;
        esac
      fi
      [[ $has_aab -eq 1 ]] || _cfg_err "$dl.playstore needs 'aab' in $label.artifacts (Play only accepts app bundles)"
      cfg_has '.app.android_package_name' \
        || _cfg_err "app.android_package_name is required when the playstore destination is enabled"
    fi
  fi
  if cfg_has "$d.firebase" && _cfg_expect_type "$d.firebase" "$dl.firebase" '!!map'; then
    _cfg_known_keys "$d.firebase" "$dl.firebase" enabled groups testers
    if _cfg_dest_enabled "$d.firebase" "$dl.firebase"; then
      _cfg_expect_type "$d.firebase.groups" "$dl.firebase.groups" '!!str' || true
      _cfg_expect_type "$d.firebase.testers" "$dl.firebase.testers" '!!str' || true
      if [[ $has_apk -eq 0 ]]; then
        _CFG_WARNINGS+=("$dl.firebase: no 'apk' in artifacts, so the AAB will be uploaded; that only works if the Firebase project is linked to Google Play")
      fi
    fi
  fi
  if cfg_has "$d.drive" && _cfg_expect_type "$d.drive" "$dl.drive" '!!map'; then
    _cfg_known_keys "$d.drive" "$dl.drive" enabled folder_id
    if _cfg_dest_enabled "$d.drive" "$dl.drive"; then
      _cfg_validate_folder_id "$d.drive.folder_id" "$dl.drive.folder_id"
    fi
  fi
}

# _cfg_dest_enabled <path> <label> — require `enabled: true|false`; 0 if true.
_cfg_dest_enabled() {
  if ! cfg_has "$1.enabled"; then
    _cfg_err "$2.enabled is required (true to send builds there, false to skip)"
    return 1
  fi
  _cfg_expect_type "$1.enabled" "$2.enabled" '!!bool' || return 1
  [[ "$(cfg "$1.enabled")" == "true" ]]
}

_cfg_validate_ios() {
  local p=".environments.$1.ios" label="environments.$1.ios"
  _cfg_expect_type "$p" "$label" '!!map' || return 0
  _cfg_known_keys "$p" "$label" display_name app_icon google_service_info build_settings target destinations

  if _cfg_expect_type "$p.display_name" "$label.display_name" '!!str'; then
    [[ "$(cfg "$p.display_name")" != *"//"* ]] || _cfg_err "$label.display_name must not contain '//' (it starts a comment in .xcconfig files)"
  fi
  if _cfg_expect_type "$p.target" "$label.target" '!!str'; then
    [[ "$(cfg "$p.target")" == *.dart ]] || _cfg_err "$label.target must point to a .dart file"
  fi
  if _cfg_expect_type "$p.app_icon" "$label.app_icon" '!!str'; then
    [[ "$(cfg "$p.app_icon")" =~ ^[A-Za-z0-9_-]+$ ]] \
      || _cfg_err "$label.app_icon must be an asset catalog icon set name like 'AppIcon-UAT'"
  fi
  if _cfg_expect_type "$p.google_service_info" "$label.google_service_info" '!!str'; then
    [[ "$(cfg "$p.google_service_info")" == *.plist ]] \
      || _cfg_err "$label.google_service_info must point to a .plist file"
  fi
  if _cfg_expect_type "$p.build_settings" "$label.build_settings" '!!map'; then
    local key t
    while IFS= read -r key; do
      [[ -z "$key" ]] && continue
      [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]] \
        || _cfg_err "$label.build_settings: '$key' is not a valid build setting name (UPPER_SNAKE_CASE)"
      case "$key" in
        APP_DISPLAY_NAME | ASSETCATALOG_COMPILER_APPICON_NAME)
          _cfg_err "$label.build_settings.$key: use display_name / app_icon instead" ;;
      esac
      t="$(yq e ".environments.$1.ios.build_settings[\"$key\"] | type" "$FLUTTER_CI_CONFIG")"
      case "$t" in
        '!!str' | '!!int' | '!!bool' | '!!float') ;;
        *) _cfg_err "$label.build_settings.$key must be a plain value (got ${t#!!})" ;;
      esac
    done < <(yq e "($p.build_settings) | keys | .[]" "$FLUTTER_CI_CONFIG")
  fi

  if cfg_has "$p.destinations"; then
    _cfg_err "$label.destinations: iOS builds go to TestFlight only (set up in the Xcode Cloud workflow); remove this block"
  fi
}

# validate_config <file> [env] — returns 1 after printing every problem found.
validate_config() {
  local file="$1" want_env="${2:-}"
  _CFG_ERRORS=()
  _CFG_WARNINGS=()
  config_load "$file"

  if [[ "$(_cfg_type '.')" != "!!map" ]]; then
    _cfg_err "the file must be a YAML mapping with 'version', 'app' and 'environments'"
  else
    _cfg_known_keys '.' "top level" version app environments

    if ! cfg_has '.version'; then
      _cfg_err "version is required (current schema: version: $FLUTTER_CI_SCHEMA_VERSION)"
    elif [[ "$(cfg '.version')" != "$FLUTTER_CI_SCHEMA_VERSION" ]]; then
      _cfg_err "version: $(cfg '.version') is not supported by this flutter-ci release (expected $FLUTTER_CI_SCHEMA_VERSION). See docs/MAINTAINING.md for migrations"
    fi

    # ---- app
    if ! cfg_has '.app'; then
      _cfg_err "app is required"
    elif _cfg_expect_type '.app' 'app' '!!map'; then
      _cfg_known_keys '.app' 'app' name flutter_version_file java_version prod_branches \
        build_number_offset run_tests run_analyze obfuscate android_package_name github_release
      if ! cfg_has '.app.name'; then
        _cfg_err "app.name is required"
      else
        _cfg_expect_type '.app.name' 'app.name' '!!str' || true
      fi
      if _cfg_expect_type '.app.flutter_version_file' 'app.flutter_version_file' '!!str'; then
        case "$(cfg '.app.flutter_version_file')" in
          .fvmrc | pubspec.yaml) ;;
          *) _cfg_err "app.flutter_version_file must be '.fvmrc' or 'pubspec.yaml'" ;;
        esac
      fi
      if _cfg_expect_type '.app.java_version' 'app.java_version' '!!str' '!!int'; then
        [[ "$(cfg '.app.java_version')" =~ ^[0-9]+$ ]] \
          || _cfg_err "app.java_version must be a major version like \"17\""
      fi
      if _cfg_expect_type '.app.prod_branches' 'app.prod_branches' '!!seq'; then
        [[ "$(yq e '.app.prod_branches | length' "$FLUTTER_CI_CONFIG")" -gt 0 ]] \
          || _cfg_err "app.prod_branches must list at least one branch"
        local b
        while IFS= read -r b; do
          [[ "$b" =~ ^[A-Za-z0-9._/-]+$ ]] || _cfg_err "app.prod_branches: '$b' is not a valid branch name"
        done < <(cfg_list '.app.prod_branches')
      fi
      if _cfg_expect_type '.app.build_number_offset' 'app.build_number_offset' '!!int'; then
        [[ "$(cfg '.app.build_number_offset')" =~ ^[0-9]+$ ]] \
          || _cfg_err "app.build_number_offset must be 0 or a positive integer"
      fi
      local flag
      for flag in run_tests run_analyze obfuscate; do
        _cfg_expect_type ".app.$flag" "app.$flag" '!!bool' || true
      done
      if _cfg_expect_type '.app.android_package_name' 'app.android_package_name' '!!str'; then
        [[ "$(cfg '.app.android_package_name')" =~ ^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$ ]] \
          || _cfg_err "app.android_package_name must look like com.example.app"
      fi
      if _cfg_expect_type '.app.github_release' 'app.github_release' '!!map'; then
        _cfg_known_keys '.app.github_release' 'app.github_release' enabled attach_artifacts
        _cfg_expect_type '.app.github_release.enabled' 'app.github_release.enabled' '!!bool' || true
        _cfg_expect_type '.app.github_release.attach_artifacts' 'app.github_release.attach_artifacts' '!!bool' || true
      fi
    fi

    # ---- environments
    if ! cfg_has '.environments'; then
      _cfg_err "environments is required (with 'uat' and/or 'prod')"
    elif _cfg_expect_type '.environments' 'environments' '!!map'; then
      _cfg_known_keys '.environments' 'environments' uat prod
      local env
      for env in uat prod; do
        cfg_has ".environments.$env" || continue
        if [[ "$(_cfg_type ".environments.$env")" != "!!map" ]]; then
          _cfg_err "environments.$env must be a mapping"
          continue
        fi
        _cfg_known_keys ".environments.$env" "environments.$env" dart_define_file android ios
        if _cfg_expect_type ".environments.$env.dart_define_file" "environments.$env.dart_define_file" '!!str'; then
          [[ "$(cfg ".environments.$env.dart_define_file")" == *.json ]] \
            || _cfg_err "environments.$env.dart_define_file must point to a .json file"
        fi
        _cfg_validate_android "$env"
        _cfg_validate_ios "$env"
      done
      if [[ -n "$want_env" ]] && ! cfg_has ".environments.$want_env"; then
        _cfg_err "environments.$want_env is missing, but this tag builds the '$want_env' environment"
      fi
    fi
  fi

  local w
  for w in ${_CFG_WARNINGS[@]+"${_CFG_WARNINGS[@]}"}; do log_warn "$file: $w"; done

  if [[ ${#_CFG_ERRORS[@]} -gt 0 ]]; then
    local e msg="Invalid config $file:"
    for e in "${_CFG_ERRORS[@]}"; do msg="$msg"$'\n'"  - $e"; done
    log_error "$msg" "CONFIG_REFERENCE.md"
    return 1
  fi
  return 0
}

_read_config_main() {
  local cmd="${1:-}"
  case "$cmd" in
    validate)
      [[ $# -ge 2 ]] || { echo "usage: read_config.sh validate <config.yaml> [env]" >&2; exit 2; }
      ensure_yq
      validate_config "$2" "${3:-}" || exit 1
      log_info "Config $2 is valid."
      ;;
    get)
      [[ $# -eq 3 ]] || { echo "usage: read_config.sh get <config.yaml> <yq-path>" >&2; exit 2; }
      ensure_yq
      config_load "$2"
      cfg "$3"
      printf '\n'
      ;;
    *)
      echo "usage: read_config.sh validate|get ..." >&2
      exit 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  _read_config_main "$@"
fi
