#!/bin/bash
# Small helpers shared by the build / distribution scripts.

if [[ -n "${_FLUTTER_CI_UTIL_SH:-}" ]]; then return 0; fi
_FLUTTER_CI_UTIL_SH=1

_UTIL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common/log.sh
source "$_UTIL_DIR/log.sh"

# b64decode — decode stdin (GNU and BSD/macOS base64; tolerates newlines).
b64decode() {
  tr -d ' \r\n' | { base64 --decode 2>/dev/null || base64 -D; }
}

# ci_temp_dir — a private scratch dir outside the app's working tree.
ci_temp_dir() {
  local base="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
  local dir="${base%/}/flutter-ci"
  mkdir -p "$dir"
  chmod 700 "$dir"
  printf '%s' "$dir"
}

# tools_dir — where downloaded CLIs (firebase) are cached.
tools_dir() {
  local dir="${FLUTTER_CI_TOOLS_DIR:-$HOME/.flutter-ci/bin}"
  mkdir -p "$dir"
  printf '%s' "$dir"
}

# secret_from_env <NAME> — print the value of NAME, or the decoded value of
# NAME_BASE64 (Xcode Cloud stores secrets base64-encoded). Empty if unset.
secret_from_env() {
  local name="$1" b64_name="${1}_BASE64"
  if [[ -n "${!name:-}" ]]; then
    printf '%s' "${!name}"
  elif [[ -n "${!b64_name:-}" ]]; then
    printf '%s' "${!b64_name}" | b64decode
  fi
}

# write_secret_file <path> — write stdin to <path> with 0600 permissions.
write_secret_file() {
  local path="$1"
  (umask 077 && cat >"$path")
}

# slugify <text> — safe file name component.
slugify() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-' | sed -e 's/--*/-/g' -e 's/^-//' -e 's/-$//'
}
