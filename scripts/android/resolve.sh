#!/bin/bash
# GitHub Actions: resolve the build context for an Android release.
#
# Env (set by android-release.yml):
#   CONFIG_PATH, TAG_OVERRIDE, DRY_RUN, GITHUB_REF_TYPE, GITHUB_REF_NAME,
#   GITHUB_RUN_NUMBER
# Writes all context keys plus BUILD_NUMBER and DRY_RUN to $GITHUB_OUTPUT.
set -euo pipefail

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common/context.sh
source "$_DIR/../common/context.sh"

# Play's maximum versionCode.
MAX_VERSION_CODE=2100000000

tag=""
if [[ -n "${TAG_OVERRIDE:-}" ]]; then
  if [[ "${DRY_RUN:-false}" != "true" ]]; then
    die "The 'tag' input is only allowed together with dry-run: true. Real builds are triggered by pushing a tag." \
      "TAGGING_AND_RELEASES.md#tag-format"
  fi
  tag="$TAG_OVERRIDE"
elif [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
  tag="$GITHUB_REF_NAME"
else
  die "This workflow must be triggered by pushing a tag (got ref '${GITHUB_REF:-?}'). Check 'on: push: tags' in .github/workflows/release.yml." \
    "TAGGING_AND_RELEASES.md#tag-format"
fi

resolve_context . "${CONFIG_PATH:-.ci/config.yaml}" "$tag" android || exit 1

run_number="${GITHUB_RUN_NUMBER:?GITHUB_RUN_NUMBER not set}"
build_number=$((run_number + BUILD_NUMBER_OFFSET))
if [[ $build_number -gt $MAX_VERSION_CODE ]]; then
  die "Build number $build_number exceeds Play's maximum versionCode ($MAX_VERSION_CODE)." "CONFIG_REFERENCE.md#app"
fi
_ctx BUILD_NUMBER "$build_number"
_ctx DRY_RUN "${DRY_RUN:-false}"

context_to_github_output
print_context >&2
