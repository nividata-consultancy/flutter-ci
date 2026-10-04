#!/bin/bash
# Logging helpers shared by every flutter-ci script.
#
# On GitHub Actions messages use workflow commands (::error:: etc.) so they
# show up as annotations. Everywhere else (Xcode Cloud, local) they use plain
# "ERROR:" / "WARNING:" prefixes on stderr.
#
# Must stay compatible with /bin/bash 3.2 (macOS / Xcode Cloud).

# Guard against double sourcing.
if [[ -n "${_FLUTTER_CI_LOG_SH:-}" ]]; then return 0; fi
_FLUTTER_CI_LOG_SH=1

FLUTTER_CI_DOCS_BASE="${FLUTTER_CI_DOCS_BASE:-https://github.com/OWNER/flutter-ci/blob/v1/docs}"

_is_github() { [[ "${GITHUB_ACTIONS:-}" == "true" ]]; }

# doc_url <FILE.md#anchor>
doc_url() { printf '%s/%s' "$FLUTTER_CI_DOCS_BASE" "$1"; }

log_info() { printf '%s\n' "$*" >&2; }

log_step() {
  if _is_github; then printf '\n▶ %s\n' "$*" >&2; else printf '\n==> %s\n' "$*" >&2; fi
}

log_warn() {
  if _is_github; then printf '::warning::%s\n' "$*" >&2; else printf 'WARNING: %s\n' "$*" >&2; fi
}

# log_error <message> [doc-ref]
log_error() {
  local msg="$1" doc="${2:-}"
  if [[ -n "$doc" ]]; then msg="$msg (see $(doc_url "$doc"))"; fi
  if _is_github; then
    # Workflow commands are single-line: encode newlines.
    msg="${msg//'%'/'%25'}"
    msg="${msg//$'\n'/'%0A'}"
    printf '::error::%s\n' "$msg" >&2
  else
    printf 'ERROR: %s\n' "$msg" >&2
  fi
}

# die <message> [doc-ref]  — log an error and exit 1.
die() {
  log_error "$@"
  exit 1
}

# mask <value> — hide a value from GitHub logs. No-op elsewhere.
mask() {
  local v="${1:-}"
  [[ -z "$v" ]] && return 0
  if _is_github; then
    local line
    while IFS= read -r line; do
      [[ -n "$line" ]] && printf '::add-mask::%s\n' "$line"
    done <<<"$v"
  fi
  return 0
}

# set_output <key> <value> — expose a value to later GitHub steps
# ($GITHUB_OUTPUT) and print KEY=VALUE for humans / other platforms.
set_output() {
  local key="$1" value="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    if [[ "$value" == *$'\n'* ]]; then
      local delim="EOF_$RANDOM$RANDOM"
      printf '%s<<%s\n%s\n%s\n' "$key" "$delim" "$value" "$delim" >>"$GITHUB_OUTPUT"
    else
      printf '%s=%s\n' "$key" "$value" >>"$GITHUB_OUTPUT"
    fi
  fi
}
