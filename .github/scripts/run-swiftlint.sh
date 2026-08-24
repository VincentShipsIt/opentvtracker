#!/usr/bin/env bash
set -Eeuo pipefail

readonly SWIFTLINT_VERSION="0.65.0"
readonly SWIFTLINT_ARCHIVE_SHA256="d6cb0aa7a2f5f1ef306fc9e37bcb54dc9a26facc8f7784ac0c3dd3eccf5c6ba6"
readonly SWIFTLINT_ARCHIVE_URL="https://github.com/realm/SwiftLint/releases/download/${SWIFTLINT_VERSION}/portable_swiftlint.zip"

ROOT="${OPENTV_SWIFTLINT_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
readonly ROOT
readonly SWIFTLINT_CONFIG="$ROOT/.swiftlint.yml"

SWIFTLINT_BINARY=""
SWIFTLINT_TEMP=""

cleanup() {
  if [[ -n "$SWIFTLINT_TEMP" && -d "$SWIFTLINT_TEMP" ]]; then
    rm -rf "$SWIFTLINT_TEMP"
  fi
}
trap cleanup EXIT

die() {
  echo "::error::$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command is unavailable: $1"
}

require_file() {
  [[ -f "$1" ]] || die "Required file is missing: ${1#"$ROOT/"}"
}

verify_swiftlint_archive() {
  local archive="$1"
  local actual_sha=""
  require_command shasum
  require_file "$archive"
  actual_sha="$(shasum -a 256 "$archive" | awk '{print $1}')"
  [[ "$actual_sha" == "$SWIFTLINT_ARCHIVE_SHA256" ]] \
    || die "SwiftLint archive checksum mismatch: expected $SWIFTLINT_ARCHIVE_SHA256, got $actual_sha"
}

resolve_swiftlint() {
  local archive=""
  local discovered=""
  local version_output=""

  if [[ -n "${OPENTV_SWIFTLINT_BIN:-}" ]]; then
    [[ "${OPENTV_SWIFTLINT_TEST_MODE:-}" == "1" ]] \
      || die "OPENTV_SWIFTLINT_BIN is reserved for the isolated helper test harness"
    SWIFTLINT_BINARY="$OPENTV_SWIFTLINT_BIN"
    [[ -x "$SWIFTLINT_BINARY" ]] || die "OPENTV_SWIFTLINT_BIN is not executable"
  else
    require_command curl
    require_command shasum
    require_command unzip
    SWIFTLINT_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/opentv-swiftlint.XXXXXX")"
    archive="$SWIFTLINT_TEMP/portable_swiftlint.zip"
    curl --fail --location --silent --show-error \
      --connect-timeout 15 --max-time 120 --retry 3 --retry-all-errors \
      "$SWIFTLINT_ARCHIVE_URL" -o "$archive"
    verify_swiftlint_archive "$archive"
    unzip -q "$archive" -d "$SWIFTLINT_TEMP/unpacked"
    discovered="$(find "$SWIFTLINT_TEMP/unpacked" -type f -name swiftlint -print -quit)"
    [[ -n "$discovered" ]] || die "Verified SwiftLint archive did not contain a swiftlint binary"
    chmod +x "$discovered"
    SWIFTLINT_BINARY="$discovered"
  fi

  version_output="$("$SWIFTLINT_BINARY" version)"
  [[ "$version_output" == "$SWIFTLINT_VERSION" ]] \
    || die "Expected SwiftLint $SWIFTLINT_VERSION, got: $version_output"
  if [[ "${OPENTV_SWIFTLINT_TEST_MODE:-}" == "1" ]]; then
    echo "Using the isolated SwiftLint $SWIFTLINT_VERSION test double."
  else
    echo "Using SwiftLint $SWIFTLINT_VERSION from the checksum-pinned release."
  fi
}

main() {
  [[ $# -eq 0 ]] || die "Usage: $0"
  require_file "$SWIFTLINT_CONFIG"
  resolve_swiftlint
  cd "$ROOT"
  "$SWIFTLINT_BINARY" lint --strict --no-cache
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
