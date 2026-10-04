#!/bin/bash
# Build short release notes for testers (TestFlight, Firebase, Play, GitHub).
#
#   [UAT] v1.4.0-beta.1 · abc1234
#   Fixed login crash, added dark mode        <- the tag message, if any
#   - Fix login crash                         <- otherwise recent commits
#
# Developers write notes by creating an annotated tag:
#   git tag -a v1.4.0-beta.1 -m "Fixed login crash, added dark mode"
# A lightweight tag (git tag v1.4.0-beta.1) falls back to commit subjects.
#
# The first line is how testers tell UAT and PROD builds apart: both carry
# the same version number in TestFlight / Play.
#
# CLI: release_notes.sh <tag> [--max-bytes N] [--max-commits N] [--commit REV] [--with-commits]
#   --max-bytes    hard size limit in bytes (default 1000; TestFlight <1 KB,
#                  Play "what's new" is 500 characters)
#   --max-commits  number of commit subjects (default 5)
#   --with-commits list commits even when the tag has a message
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

# _rn_tag_message <tag> — message of an annotated tag (empty for lightweight tags).
_rn_tag_message() {
  local tag="$1"
  if [[ "$(git cat-file -t "refs/tags/$tag" 2>/dev/null)" != "tag" ]]; then
    # CI clones may only have a lightweight copy of the tag; fetch the real one.
    git fetch --quiet --force --no-tags "${FLUTTER_CI_GIT_REMOTE:-origin}" "+refs/tags/$tag:refs/tags/$tag" >/dev/null 2>&1 || true
  fi
  [[ "$(git cat-file -t "refs/tags/$tag" 2>/dev/null)" == "tag" ]] || return 0
  git for-each-ref --format='%(contents)' "refs/tags/$tag" \
    | sed -e '/^-----BEGIN PGP SIGNATURE-----$/,$d' -e '/^-----BEGIN SSH SIGNATURE-----$/,$d' \
    | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}'
}

# _rn_append <line> — add a line to $out if it fits in $max_bytes.
_rn_append() {
  if [[ $(( $(_rn_bytes "$out") + 1 + $(_rn_bytes "$1") )) -gt $max_bytes ]]; then
    return 1
  fi
  out="$out"$'\n'"$1"
}

release_notes() {
  local tag="$1" max_bytes="${2:-1000}" max_commits="${3:-5}" commit="${4:-HEAD}" with_commits="${5:-false}"
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

  local message line
  message="$(_rn_tag_message "$TAG")"
  if [[ -n "$message" ]]; then
    while IFS= read -r line; do
      _rn_append "$line" || break
    done <<<"$message"
    if [[ "$with_commits" != "true" ]]; then
      printf '%s\n' "$out" | _rn_trim_bytes "$max_bytes"
      return 0
    fi
    _rn_append "" || true
    _rn_append "Changes:" || true
  fi

  local prev="" range="$commit"
  if [[ "$ENVIRONMENT" == "prod" ]]; then
    prev="$(git describe --tags --abbrev=0 --match 'v[0-9]*' --exclude '*-*' "$commit^" 2>/dev/null || true)"
  else
    prev="$(git describe --tags --abbrev=0 --match 'v[0-9]*' "$commit^" 2>/dev/null || true)"
  fi
  [[ -n "$prev" ]] && range="$prev..$commit"

  local subject
  while IFS= read -r subject; do
    [[ -z "$subject" ]] && continue
    _rn_append "- $(printf '%s' "$subject" | _rn_trim_bytes 100)" || break
  done < <(git log --no-merges --format='%s' -n "$max_commits" "$range" 2>/dev/null || true)

  printf '%s\n' "$out" | _rn_trim_bytes "$max_bytes"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  _tag="" _max_bytes=1000 _max_commits=5 _commit=HEAD _with_commits=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max-bytes) _max_bytes="$2"; shift 2 ;;
      --max-commits) _max_commits="$2"; shift 2 ;;
      --commit) _commit="$2"; shift 2 ;;
      --with-commits) _with_commits=true; shift ;;
      -*) echo "unknown option $1" >&2; exit 2 ;;
      *) _tag="$1"; shift ;;
    esac
  done
  [[ -n "$_tag" ]] || { echo "usage: release_notes.sh <tag> [--max-bytes N] [--max-commits N] [--commit REV]" >&2; exit 2; }
  release_notes "$_tag" "$_max_bytes" "$_max_commits" "$_commit" "$_with_commits"
fi
