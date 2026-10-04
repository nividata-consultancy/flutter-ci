#!/bin/bash
# flutter-ci bootstrap — keep this file tiny; all logic lives in nividata-consultancy/flutter-ci.
# Pin the library with the FLUTTER_CI_REF env var in Xcode Cloud (default: v1).
set -euo pipefail
DIR="$CI_PRIMARY_REPOSITORY_PATH/.flutter-ci"
if [[ ! -f "$DIR/scripts/xcode-cloud/post_clone.sh" ]]; then
  mkdir -p "$DIR"
  curl -fsSL --retry 3 "https://codeload.github.com/nividata-consultancy/flutter-ci/tar.gz/${FLUTTER_CI_REF:-v1}" | tar -xz -C "$DIR" --strip-components 1
fi
exec /bin/bash "$DIR/scripts/xcode-cloud/post_clone.sh"
