#!/bin/bash
# Build short release notes from the tag and recent commits.
#
#   [UAT] v1.4.0-beta.1 · abc1234
#   - Fix login crash
#   - Add dark mode
#
# The first line is how testers tell UAT and PROD builds apart: both carry
# the same version number in TestFlight / Play.
#
# CLI: release_notes.sh <tag> [--max-bytes N] [--max-commits N] [--commit REV]
#   --max-bytes    hard size limit in bytes (default 1000; TestFlight <1 KB,
#                  Play "what's new" is 500 characters)
#   --max-commits  number of commit subjects (default 5)
#
# Commits are those since the previous tag (for prod: the previous prod tag).
# Never fails because of missing git history; it falls back to the header.

_RELEASE_NOTES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common/parse_tag.sh
source "$_RELEASE_NOTES_DIR/parse_tag.sh"

# _rn_trim_bytes <max> — cut stdin to <max> bytes without splitting UTF-8 chars.
_rn_trim_bytes() {
  LC_ALL=C head -c "$1" | iconv -c -f UTF-8 -t UTF-8 2>/dev/null || true
}

_rn_bytes() { printf '%s' "$1" | LC_ALL=C wc -c | tr -d ' '; }

release_notes() {
  local tag="$1" max_bytes="${2:-1000}" max_commits="${3:-5}" commit="${4:-HEAD}"
  parse_tag "$tag" || return 1

  local label="UAT"
  [[ "$ENVIRONMENT" == "prod" ]] && label="PROD"

  local short
  short="$(git rev-parse --short=7 "$commit" 2>/dev/null || printf '%s' "${commit:0:7}")"
  local out="[$label] $TAG · $short"

  # Best effort: a bit more history in shallow clones (Xcode Cloud).
  if [[ "$(git rev-parse --is-shallow-repository 2>/dev/null)" == "true" ]]; then
    git fetch --quiet --deepen=50 --tags "${FLUTTER_CI_GIT_REMOTE:-origin}" >/dev/null 2>&1 || true
  fi

  local prev="" range="$commit"
  if [[ "$ENVIRONMENT" == "prod" ]]; then
    prev="$(git describe --tags --abbrev=0 --match 'v[0-9]*' --exclude '*-*' "$commit^" 2>/dev/null || true)"
  else
    prev="$(git describe --tags --abbrev=0 --match 'v[0-9]*' "$commit^" 2>/dev/null || true)"
  fi
  [[ -n "$prev" ]] && range="$prev..$commit"

  local subject line
  while IFS= read -r subject; do
    [[ -z "$subject" ]] && continue
    line="- $(printf '%s' "$subject" | _rn_trim_bytes 100)"
    if [[ $(( $(_rn_bytes "$out") + 1 + $(_rn_bytes "$line") )) -gt $max_bytes ]]; then
      break
    fi
    out="$out"$'\n'"$line"
  done < <(git log --no-merges --format='%s' -n "$max_commits" "$range" 2>/dev/null || true)

  printf '%s\n' "$out" | _rn_trim_bytes "$max_bytes"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  _tag="" _max_bytes=1000 _max_commits=5 _commit=HEAD
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max-bytes) _max_bytes="$2"; shift 2 ;;
      --max-commits) _max_commits="$2"; shift 2 ;;
      --commit) _commit="$2"; shift 2 ;;
      -*) echo "unknown option $1" >&2; exit 2 ;;
      *) _tag="$1"; shift ;;
    esac
  done
  [[ -n "$_tag" ]] || { echo "usage: release_notes.sh <tag> [--max-bytes N] [--max-commits N] [--commit REV]" >&2; exit 2; }
  release_notes "$_tag" "$_max_bytes" "$_max_commits" "$_commit"
fi
