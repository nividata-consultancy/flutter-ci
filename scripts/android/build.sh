#!/bin/bash
# Build the Android AAB and/or APK (run from the app root).
#
# Env (from resolve.sh outputs): ARTIFACTS ("aab apk"), FLAVOR, TARGET,
#   BUILD_NAME, BUILD_NUMBER, APP_NAME, ENVIRONMENT,
#   BUILD_ARGS (extra flags from the config, one per line)
# Optional: FLUTTER_CI_PRINT_ARGS=1 prints the flutter args and exits (tests).
#
# Copies outputs to build/flutter-ci-artifacts/ and writes AAB_PATH,
# APK_PATH, MAPPING_PATH, ARTIFACTS_DIR to $GITHUB_OUTPUT.
set -euo pipefail

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common/util.sh
source "$_DIR/../common/util.sh"

OUT_DIR="build/flutter-ci-artifacts"

# flutter_args — shared args for every `flutter build` (one per line).
flutter_args() {
  printf '%s\n' --release
  [[ -n "${FLAVOR:-}" ]] && printf '%s\n' --flavor "$FLAVOR"
  [[ -n "${TARGET:-}" ]] && printf '%s\n' --target "$TARGET"
  printf '%s\n' "--build-name=${BUILD_NAME:?BUILD_NAME not set}" "--build-number=${BUILD_NUMBER:?BUILD_NUMBER not set}"
  [[ -n "${BUILD_ARGS:-}" ]] && printf '%s\n' "$BUILD_ARGS"
  return 0
}

# _newest <dir> <pattern> — newest matching file newer than the build marker.
_newest() {
  [[ -d "$1" ]] || return 0
  find "$1" -type f -name "$2" -newer "$MARKER_FILE" -print 2>/dev/null | head -n 1
}

main() {
  local args=() line
  while IFS= read -r line; do args+=("$line"); done < <(flutter_args)

  if [[ "${FLUTTER_CI_PRINT_ARGS:-}" == "1" ]]; then
    printf '%s\n' "${args[@]}"
    return 0
  fi

  mkdir -p build "$OUT_DIR"
  MARKER_FILE="build/.flutter-ci-build-start"
  : >"$MARKER_FILE"
  sleep 1

  local base
  base="$(slugify "${APP_NAME:-app}")-${ENVIRONMENT:-env}-${BUILD_NAME}-${BUILD_NUMBER}"
  local aab="" apk="" mapping="" kind
  for kind in ${ARTIFACTS:-aab}; do
    case "$kind" in
      aab)
        log_step "flutter build appbundle ${args[*]}"
        flutter build appbundle "${args[@]}"
        local src
        src="$(_newest build/app/outputs/bundle '*.aab')"
        [[ -n "$src" ]] || die "flutter build appbundle produced no .aab." "TROUBLESHOOTING.md#android-build-fails"
        aab="$OUT_DIR/$base.aab"
        cp "$src" "$aab"
        ;;
      apk)
        apk="$OUT_DIR/$base.apk"
        # With an AAB already built, make the APK from it: a second Gradle
        # build takes as long again and can fill the runner's disk.
        if [[ -n "$aab" ]]; then
          "$_DIR/apk_from_aab.sh" "$aab" "$apk"
          continue
        fi
        log_step "flutter build apk ${args[*]}"
        flutter build apk "${args[@]}"
        local src=""
        if [[ -n "${FLAVOR:-}" && -f "build/app/outputs/flutter-apk/app-$FLAVOR-release.apk" ]]; then
          src="build/app/outputs/flutter-apk/app-$FLAVOR-release.apk"
        elif [[ -f build/app/outputs/flutter-apk/app-release.apk ]]; then
          src="build/app/outputs/flutter-apk/app-release.apk"
        else
          src="$(_newest build/app/outputs '*-release.apk')"
        fi
        [[ -n "$src" ]] || die "flutter build apk produced no .apk." "TROUBLESHOOTING.md#android-build-fails"
        cp "$src" "$apk"
        ;;
      *) die "Unknown artifact type '$kind'." "CONFIG_REFERENCE.md#android" ;;
    esac
  done

  local map_src
  map_src="$(_newest build/app/outputs/mapping 'mapping.txt')"
  if [[ -n "$map_src" ]]; then
    mapping="$OUT_DIR/$base-mapping.txt"
    cp "$map_src" "$mapping"
  fi

  log_info "Artifacts:"
  ls -l "$OUT_DIR" >&2
  set_output AAB_PATH "$aab"
  set_output APK_PATH "$apk"
  set_output MAPPING_PATH "$mapping"
  set_output ARTIFACTS_DIR "$OUT_DIR"
  set_output ARTIFACT_BASENAME "$base"
}

main "$@"
