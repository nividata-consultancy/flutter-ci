#!/bin/bash
# Make a universal APK from an AAB with bundletool, instead of a second
# Gradle build (run from the app root).
#
#   apk_from_aab.sh <app.aab> <out.apk>
#
# Signs with the upload key from android/key.properties (written by
# signing.sh), the same key Gradle signs the AAB with. Without key.properties
# (a dry run without signing secrets) a throwaway key is used.
# Secrets are passed to bundletool in files, never on the command line.
set -euo pipefail

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common/util.sh
source "$_DIR/../common/util.sh"

BUNDLETOOL_VERSION="1.18.3"
BUNDLETOOL_SHA256="a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29"
KEY_PROPERTIES="android/key.properties"

# _prop <key> — value from key.properties, with Java's `\\` unescaped.
_prop() {
  sed -n "s/^$1=//p" "$KEY_PROPERTIES" | head -n 1 | sed 's/\\\\/\\/g'
}

# _sha256 <file>
_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# _bundletool — print the path of the verified bundletool jar (downloaded once).
_bundletool() {
  local jar
  jar="$(ci_temp_dir)/bundletool-$BUNDLETOOL_VERSION.jar"
  if [[ ! -f "$jar" ]] || [[ "$(_sha256 "$jar")" != "$BUNDLETOOL_SHA256" ]]; then
    log_info "Downloading bundletool $BUNDLETOOL_VERSION"
    curl -fsSL --retry 3 -o "$jar.part" \
      "https://github.com/google/bundletool/releases/download/$BUNDLETOOL_VERSION/bundletool-all-$BUNDLETOOL_VERSION.jar" \
      || die "Could not download bundletool $BUNDLETOOL_VERSION." "TROUBLESHOOTING.md#android-build-fails"
    [[ "$(_sha256 "$jar.part")" == "$BUNDLETOOL_SHA256" ]] \
      || { rm -f "$jar.part"; die "bundletool $BUNDLETOOL_VERSION checksum mismatch." "TROUBLESHOOTING.md#android-build-fails"; }
    mv "$jar.part" "$jar"
  fi
  printf '%s' "$jar"
}

main() {
  local aab="$1" out="$2"
  [[ -f "$aab" ]] || die "No AAB at '$aab'." "TROUBLESHOOTING.md#android-build-fails"
  command -v java >/dev/null 2>&1 || die "java is not on PATH." "TROUBLESHOOTING.md#android-build-fails"

  local work ks alias
  work="$(ci_temp_dir)/apk-from-aab"
  rm -rf "$work"
  mkdir -p "$work"
  chmod 700 "$work"

  if [[ -f "$KEY_PROPERTIES" ]]; then
    ks="$(_prop storeFile)"
    alias="$(_prop keyAlias)"
    [[ "$ks" == /* ]] || ks="android/app/$ks" # Gradle resolves it from android/app
    [[ -f "$ks" && -n "$alias" ]] || die "$KEY_PROPERTIES has no usable storeFile/keyAlias." "TROUBLESHOOTING.md#android-build-fails"
    _prop storePassword | write_secret_file "$work/ks.pass"
    _prop keyPassword | write_secret_file "$work/key.pass"
  else
    log_warn "No $KEY_PROPERTIES (dry run without signing secrets): the APK is signed with a throwaway key."
    ks="$work/throwaway.jks"
    alias="flutter-ci"
    local pass
    pass="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
    printf '%s' "$pass" | write_secret_file "$work/ks.pass"
    printf '%s' "$pass" | write_secret_file "$work/key.pass"
    keytool -genkeypair -keystore "$ks" -storepass:file "$work/ks.pass" -keypass:file "$work/key.pass" \
      -alias "$alias" -dname CN=flutter-ci -keyalg RSA -keysize 2048 -validity 1 >/dev/null 2>&1 \
      || die "Could not create a throwaway signing key with keytool." "TROUBLESHOOTING.md#android-build-fails"
  fi

  local jar
  jar="$(_bundletool)"
  log_step "bundletool build-apks --mode=universal $aab"
  java -jar "$jar" build-apks --mode=universal --overwrite \
    --bundle="$aab" --output="$work/app.apks" \
    --ks="$ks" --ks-pass="file:$work/ks.pass" \
    --ks-key-alias="$alias" --key-pass="file:$work/key.pass" \
    || { rm -rf "$work"; die "bundletool could not make an APK from $aab." "TROUBLESHOOTING.md#android-build-fails"; }

  unzip -p "$work/app.apks" universal.apk >"$out"
  rm -rf "$work"
  [[ -s "$out" ]] || die "bundletool produced no universal.apk." "TROUBLESHOOTING.md#android-build-fails"
}

main "$@"
