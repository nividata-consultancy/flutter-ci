#!/bin/bash
# Prod guard: a prod tag's commit must be reachable from one of the
# configured prod branches (default: main).
#
# CLI:  prod_guard.sh <commit> <branch> [<branch>...]
# Lib:  prod_guard <commit> <branch>...
#
# Works in shallow clones (Xcode Cloud): if the repository is shallow or the
# branch is not known locally, the branch is fetched from 'origin' first.
# Set FLUTTER_CI_GIT_REMOTE to use another remote.

_PROD_GUARD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common/log.sh
source "$_PROD_GUARD_DIR/log.sh"

# _pg_unshallow — make sure enough history exists for merge-base.
_pg_unshallow() {
  local remote="$1"
  if [[ "$(git rev-parse --is-shallow-repository 2>/dev/null)" == "true" ]]; then
    log_info "Shallow clone detected; fetching full history from $remote..."
    git fetch --quiet --unshallow --no-tags "$remote" >&2 \
      || git fetch --quiet --depth=2147483647 --no-tags "$remote" >&2 \
      || return 1
  fi
}

# _pg_branch_ref <remote> <branch> — print a ref for the branch, fetching it if needed.
_pg_branch_ref() {
  local remote="$1" branch="$2"
  if ! git rev-parse --verify --quiet "refs/remotes/$remote/$branch^{commit}" >/dev/null; then
    git fetch --quiet --no-tags "$remote" "+refs/heads/$branch:refs/remotes/$remote/$branch" >&2 2>/dev/null || true
  fi
  if git rev-parse --verify --quiet "refs/remotes/$remote/$branch^{commit}" >/dev/null; then
    printf 'refs/remotes/%s/%s' "$remote" "$branch"
  elif git rev-parse --verify --quiet "refs/heads/$branch^{commit}" >/dev/null; then
    printf 'refs/heads/%s' "$branch"
  else
    return 1
  fi
}

prod_guard() {
  local commit="$1"
  shift
  local remote="${FLUTTER_CI_GIT_REMOTE:-origin}" branch ref found_any=0

  if [[ $# -eq 0 ]]; then set -- main; fi

  if ! git rev-parse --verify --quiet "$commit^{commit}" >/dev/null; then
    log_error "Prod guard: commit '$commit' is not in this clone." "TROUBLESHOOTING.md#prod-guard-rejected"
    return 1
  fi

  if git remote get-url "$remote" >/dev/null 2>&1; then
    if ! _pg_unshallow "$remote"; then
      log_error "Prod guard: could not fetch history from '$remote' to check the tag (shallow clone)." \
        "TROUBLESHOOTING.md#prod-guard-rejected"
      return 1
    fi
  fi

  for branch in "$@"; do
    if ! ref="$(_pg_branch_ref "$remote" "$branch")"; then
      log_warn "Prod guard: branch '$branch' not found locally or on '$remote'; skipping it."
      continue
    fi
    found_any=1
    if git merge-base --is-ancestor "$commit" "$ref"; then
      log_info "Prod guard: $(git rev-parse --short "$commit") is on '$branch'. OK."
      return 0
    fi
  done

  if [[ $found_any -eq 0 ]]; then
    log_error "Prod guard: none of the prod branches ($*) exist. Check app.prod_branches in .ci/config.yaml." \
      "TROUBLESHOOTING.md#prod-guard-rejected"
  else
    log_error "Prod guard: commit $(git rev-parse --short "$commit") is not on any prod branch ($*). Prod tags (vX.Y.Z) must be created on a commit already merged into a prod branch. Delete the tag (git push --delete origin <tag>), merge, and tag the merged commit." \
      "TROUBLESHOOTING.md#prod-guard-rejected"
  fi
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  [[ $# -ge 1 ]] || { echo "usage: prod_guard.sh <commit> [branch...]" >&2; exit 2; }
  prod_guard "$@" || exit 1
fi
