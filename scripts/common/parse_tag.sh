#!/bin/bash
# Single source of truth for the tag convention. Used by GitHub Actions and
# Xcode Cloud.
#
#   vX.Y.Z-beta.N  -> ENVIRONMENT=uat
#   vX.Y.Z         -> ENVIRONMENT=prod
#   anything else  -> error
#
# Usage (CLI):   parse_tag.sh <tag>          prints KEY=VALUE lines
# Usage (lib):   source parse_tag.sh; parse_tag <tag>   sets the variables
#
# Outputs: TAG, ENVIRONMENT, VERSION_NAME (X.Y.Z), VERSION_NAME_FULL
# (X.Y.Z or X.Y.Z-beta.N), IS_PRERELEASE (true|false).

_PARSE_TAG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common/log.sh
source "$_PARSE_TAG_DIR/log.sh"

FLUTTER_CI_UAT_TAG_RE='^v([0-9]+)\.([0-9]+)\.([0-9]+)-beta\.([0-9]+)$'
FLUTTER_CI_PROD_TAG_RE='^v([0-9]+)\.([0-9]+)\.([0-9]+)$'

# parse_tag <tag> — sets TAG ENVIRONMENT VERSION_NAME VERSION_NAME_FULL IS_PRERELEASE.
# Returns 1 (after logging) when the tag does not match the convention.
parse_tag() {
  local tag="${1:-}"
  tag="${tag#refs/tags/}"

  if [[ -z "$tag" ]]; then
    log_error "No tag given. Builds are triggered only by pushing a tag like v1.4.0-beta.1 (UAT) or v1.4.0 (prod)." \
      "TAGGING_AND_RELEASES.md#tag-format"
    return 1
  fi

  if [[ "$tag" =~ $FLUTTER_CI_UAT_TAG_RE ]]; then
    TAG="$tag"
    ENVIRONMENT="uat"
    VERSION_NAME="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
    VERSION_NAME_FULL="${VERSION_NAME}-beta.${BASH_REMATCH[4]}"
    IS_PRERELEASE="true"
  elif [[ "$tag" =~ $FLUTTER_CI_PROD_TAG_RE ]]; then
    TAG="$tag"
    ENVIRONMENT="prod"
    VERSION_NAME="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
    VERSION_NAME_FULL="$VERSION_NAME"
    IS_PRERELEASE="false"
  else
    log_error "Tag '$tag' does not match the tag convention. Use vX.Y.Z-beta.N for UAT (e.g. v1.4.0-beta.1) or vX.Y.Z for prod (e.g. v1.4.0)." \
      "TAGGING_AND_RELEASES.md#tag-format"
    return 1
  fi
  export TAG ENVIRONMENT VERSION_NAME VERSION_NAME_FULL IS_PRERELEASE
}

_parse_tag_main() {
  if [[ $# -ne 1 ]]; then
    echo "usage: parse_tag.sh <tag>" >&2
    exit 2
  fi
  parse_tag "$1" || exit 1
  printf 'TAG=%s\nENVIRONMENT=%s\nVERSION_NAME=%s\nVERSION_NAME_FULL=%s\nIS_PRERELEASE=%s\n' \
    "$TAG" "$ENVIRONMENT" "$VERSION_NAME" "$VERSION_NAME_FULL" "$IS_PRERELEASE"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  _parse_tag_main "$@"
fi
