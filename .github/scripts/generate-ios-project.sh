#!/usr/bin/env bash
set -Eeuo pipefail

readonly XCODEGEN_VERSION="2.46.0"
readonly XCODEGEN_ARCHIVE_SHA256="4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806"
readonly XCODEGEN_ARCHIVE_URL="https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VERSION}/xcodegen.zip"
readonly ZIPFOUNDATION_VERSION="0.9.20"
readonly ZIPFOUNDATION_REVISION="22787ffb59de99e5dc1fbfe80b19c97a904ad48d"
readonly ZIPFOUNDATION_URL="https://github.com/weichsel/ZIPFoundation"

ROOT="${OPENTV_PROJECT_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
readonly ROOT
readonly PROJECT_SPEC="$ROOT/project.yml"
readonly PBXPROJ="$ROOT/OpenTVTracker.xcodeproj/project.pbxproj"
readonly WORKSPACE_CONTENTS="$ROOT/OpenTVTracker.xcodeproj/project.xcworkspace/contents.xcworkspacedata"
readonly SHARED_SCHEME="$ROOT/OpenTVTracker.xcodeproj/xcshareddata/xcschemes/OpenTVTracker.xcscheme"
readonly PACKAGE_LOCK="$ROOT/OpenTVTracker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
readonly APP_ENTITLEMENTS="$ROOT/Config/OpenTVTracker.entitlements"
readonly WIDGET_ENTITLEMENTS="$ROOT/Config/OpenTVWidgets.entitlements"

XCODEGEN_BINARY=""
XCODEGEN_TEMP=""

cleanup() {
  if [[ -n "$XCODEGEN_TEMP" && -d "$XCODEGEN_TEMP" ]]; then
    rm -rf "$XCODEGEN_TEMP"
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

validate_project_spec() {
  require_file "$PROJECT_SPEC"

  [[ "$(grep -Fc "url: $ZIPFOUNDATION_URL" "$PROJECT_SPEC" || true)" == "1" ]] \
    || die "project.yml must declare the canonical ZIPFoundation URL exactly once"
  [[ "$(grep -Fc "exactVersion: $ZIPFOUNDATION_VERSION" "$PROJECT_SPEC" || true)" == "1" ]] \
    || die "project.yml must pin ZIPFoundation with exactVersion: $ZIPFOUNDATION_VERSION"
  if grep -Eq '^[[:space:]]+(from|majorVersion|minorVersion|minVersion|maxVersion|branch|revision):' "$PROJECT_SPEC"; then
    die "project.yml contains a non-exact Swift package requirement"
  fi
  if grep -Fq 'SystemCapabilities' "$PROJECT_SPEC"; then
    die "project.yml must not emit XcodeGen's malformed SystemCapabilities metadata"
  fi

  [[ "$(grep -Fc 'CODE_SIGN_ENTITLEMENTS: Config/OpenTVTracker.entitlements' "$PROJECT_SPEC" || true)" == "1" ]] \
    || die "project.yml must bind the app target to Config/OpenTVTracker.entitlements"
  [[ "$(grep -Fc 'CODE_SIGN_ENTITLEMENTS: Config/OpenTVWidgets.entitlements' "$PROJECT_SPEC" || true)" == "1" ]] \
    || die "project.yml must bind the widget target to Config/OpenTVWidgets.entitlements"
  [[ "$(grep -Fc 'APP_ATTEST_ENVIRONMENT: development' "$PROJECT_SPEC" || true)" == "1" ]] \
    || die "project.yml must declare the development App Attest environment"
  [[ "$(grep -Fc 'APP_ATTEST_ENVIRONMENT: production' "$PROJECT_SPEC" || true)" == "1" ]] \
    || die "project.yml must declare the production App Attest environment"
  [[ "$(grep -Fc 'PUSH_NOTIFICATIONS_ENVIRONMENT: development' "$PROJECT_SPEC" || true)" == "1" ]] \
    || die "project.yml must declare the development push environment"
  [[ "$(grep -Fc 'PUSH_NOTIFICATIONS_ENVIRONMENT: production' "$PROJECT_SPEC" || true)" == "1" ]] \
    || die "project.yml must declare the production push environment"
}

validate_entitlements() {
  require_command plutil
  require_command jq
  require_file "$APP_ENTITLEMENTS"
  require_file "$WIDGET_ENTITLEMENTS"

  plutil -lint "$APP_ENTITLEMENTS" >/dev/null \
    || die "Config/OpenTVTracker.entitlements is not a valid plist"
  plutil -lint "$WIDGET_ENTITLEMENTS" >/dev/null \
    || die "Config/OpenTVWidgets.entitlements is not a valid plist"

  if ! plutil -convert json -o - "$APP_ENTITLEMENTS" | jq -e '
    (keys | sort) == ([
      "aps-environment",
      "com.apple.developer.associated-domains",
      "com.apple.developer.devicecheck.appattest-environment",
      "com.apple.developer.icloud-container-identifiers",
      "com.apple.developer.icloud-services",
      "com.apple.developer.ubiquity-kvstore-identifier",
      "com.apple.security.application-groups"
    ] | sort)
    and .["aps-environment"] == "$(PUSH_NOTIFICATIONS_ENVIRONMENT)"
    and .["com.apple.developer.associated-domains"] == ["$(OPENROUTER_ASSOCIATED_DOMAIN)"]
    and .["com.apple.developer.devicecheck.appattest-environment"] == "$(APP_ATTEST_ENVIRONMENT)"
    and .["com.apple.developer.icloud-container-identifiers"] == ["iCloud.dev.opentvtracker.app"]
    and .["com.apple.developer.icloud-services"] == ["CloudKit"]
    and .["com.apple.developer.ubiquity-kvstore-identifier"] == "$(TeamIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)"
    and .["com.apple.security.application-groups"] == ["group.dev.opentvtracker.app"]
  ' >/dev/null; then
    die "Config/OpenTVTracker.entitlements does not match the authoritative app capability contract"
  fi

  if ! plutil -convert json -o - "$WIDGET_ENTITLEMENTS" | jq -e '
    (keys | sort) == ["com.apple.security.application-groups"]
    and .["com.apple.security.application-groups"] == ["group.dev.opentvtracker.app"]
  ' >/dev/null; then
    die "Config/OpenTVWidgets.entitlements does not match the authoritative widget capability contract"
  fi
}

validate_package_lock() {
  require_command jq
  require_file "$PACKAGE_LOCK"

  if ! jq -e \
    --arg version "$ZIPFOUNDATION_VERSION" \
    --arg revision "$ZIPFOUNDATION_REVISION" \
    --arg location "$ZIPFOUNDATION_URL" '
      .version == 3
      and (.originHash | type == "string" and test("^[0-9a-f]{64}$"))
      and (.pins | length) == 1
      and .pins[0].identity == "zipfoundation"
      and .pins[0].kind == "remoteSourceControl"
      and .pins[0].location == $location
      and .pins[0].state.version == $version
      and .pins[0].state.revision == $revision
    ' "$PACKAGE_LOCK" >/dev/null; then
    die "Package.resolved must contain only ZIPFoundation $ZIPFOUNDATION_VERSION at $ZIPFOUNDATION_REVISION"
  fi
}

validate_generated_project() {
  require_file "$PBXPROJ"
  require_file "$WORKSPACE_CONTENTS"
  require_file "$SHARED_SCHEME"

  if grep -Fq 'SystemCapabilities' "$PBXPROJ"; then
    die "Generated project contains SystemCapabilities; entitlements are the authoritative capability contract"
  fi
  [[ "$(grep -Fc 'kind = exactVersion;' "$PBXPROJ" || true)" == "1" ]] \
    || die "Generated project must contain one exact Swift package requirement"
  [[ "$(grep -Fc "version = $ZIPFOUNDATION_VERSION;" "$PBXPROJ" || true)" == "1" ]] \
    || die "Generated project must pin ZIPFoundation $ZIPFOUNDATION_VERSION"
  if grep -Fq 'kind = upToNextMajorVersion;' "$PBXPROJ"; then
    die "Generated project still permits a ZIPFoundation version range"
  fi
}

validate_contract() {
  validate_project_spec
  validate_entitlements
  validate_package_lock
  validate_generated_project
}

resolve_xcodegen() {
  local version_output=""
  local archive=""
  local discovered=""

  if [[ -n "${OPENTV_XCODEGEN_BIN:-}" ]]; then
    [[ "${OPENTV_GENERATION_TEST_MODE:-}" == "1" ]] \
      || die "OPENTV_XCODEGEN_BIN is reserved for the isolated helper test harness"
    XCODEGEN_BINARY="$OPENTV_XCODEGEN_BIN"
    [[ -x "$XCODEGEN_BINARY" ]] || die "OPENTV_XCODEGEN_BIN is not executable"
  else
    require_command curl
    require_command shasum
    require_command unzip
    XCODEGEN_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/opentv-xcodegen.XXXXXX")"
    archive="$XCODEGEN_TEMP/xcodegen.zip"
    curl --fail --location --silent --show-error \
      --connect-timeout 15 --max-time 120 --retry 3 --retry-all-errors \
      "$XCODEGEN_ARCHIVE_URL" -o "$archive"
    verify_xcodegen_archive "$archive"
    unzip -q "$archive" -d "$XCODEGEN_TEMP/unpacked"
    discovered="$(find "$XCODEGEN_TEMP/unpacked" -type f -name xcodegen -print -quit)"
    [[ -n "$discovered" ]] || die "Verified XcodeGen archive did not contain an xcodegen binary"
    chmod +x "$discovered"
    XCODEGEN_BINARY="$discovered"
  fi

  version_output="$("$XCODEGEN_BINARY" --version)"
  [[ "$version_output" == "Version: $XCODEGEN_VERSION" ]] \
    || die "Expected XcodeGen $XCODEGEN_VERSION, got: $version_output"
  if [[ "${OPENTV_GENERATION_TEST_MODE:-}" == "1" ]]; then
    echo "Using the isolated XcodeGen $XCODEGEN_VERSION test double."
  else
    echo "Using XcodeGen $XCODEGEN_VERSION from the checksum-pinned release."
  fi
}

verify_xcodegen_archive() {
  local archive="$1"
  local actual_sha=""
  require_command shasum
  require_file "$archive"
  actual_sha="$(shasum -a 256 "$archive" | awk '{print $1}')"
  [[ "$actual_sha" == "$XCODEGEN_ARCHIVE_SHA256" ]] \
    || die "XcodeGen archive checksum mismatch: expected $XCODEGEN_ARCHIVE_SHA256, got $actual_sha"
}

generate_once() {
  "$XCODEGEN_BINARY" generate \
    --spec "$PROJECT_SPEC" \
    --project "$ROOT" \
    --project-root "$ROOT" \
    --no-env \
    --quiet
  validate_generated_project
}

generated_digest() {
  shasum -a 256 "$PBXPROJ" "$WORKSPACE_CONTENTS" "$SHARED_SCHEME" \
    | shasum -a 256 \
    | awk '{print $1}'
}

assert_no_generated_drift() {
  local tracked_paths=(
    "project.yml"
    "OpenTVTracker.xcodeproj/project.pbxproj"
    "OpenTVTracker.xcodeproj/project.xcworkspace/contents.xcworkspacedata"
    "OpenTVTracker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    "OpenTVTracker.xcodeproj/xcshareddata/xcschemes/OpenTVTracker.xcscheme"
  )
  local status=""

  git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "Drift checking requires a Git worktree"
  if ! git -C "$ROOT" diff --exit-code -- "${tracked_paths[@]}"; then
    die "Generated iOS project or package contract differs from the committed files"
  fi
  status="$(git -C "$ROOT" status --porcelain --untracked-files=all -- "${tracked_paths[@]}")"
  [[ -z "$status" ]] || die "Generated iOS project contains uncommitted or untracked drift: $status"
}

main() {
  local command="${1:-check}"
  local first_digest=""
  local second_digest=""

  case "$command" in
    validate)
      [[ $# -eq 1 ]] || die "Usage: $0 {generate|check|validate}"
      validate_contract
      echo "iOS project, entitlements, and package lock satisfy the pinned contract."
      ;;
    generate)
      [[ $# -eq 1 ]] || die "Usage: $0 {generate|check|validate}"
      validate_project_spec
      validate_entitlements
      validate_package_lock
      resolve_xcodegen
      generate_once
      echo "Generated OpenTVTracker.xcodeproj deterministically."
      ;;
    check)
      [[ $# -eq 1 ]] || die "Usage: $0 {generate|check|validate}"
      validate_project_spec
      validate_entitlements
      validate_package_lock
      resolve_xcodegen
      generate_once
      first_digest="$(generated_digest)"
      generate_once
      second_digest="$(generated_digest)"
      [[ "$first_digest" == "$second_digest" ]] \
        || die "Two clean XcodeGen runs were not byte-stable: $first_digest != $second_digest"
      validate_contract
      assert_no_generated_drift
      echo "Xcode generation is byte-stable and matches the committed project."
      ;;
    *)
      die "Usage: $0 {generate|check|validate}"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
