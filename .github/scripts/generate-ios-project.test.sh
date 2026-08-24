#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
readonly ROOT
readonly SCRIPT="$ROOT/.github/scripts/generate-ios-project.sh"

TMP="$(mktemp -d)"
readonly TMP
trap 'rm -rf "$TMP"' EXIT

readonly NOOP_XCODEGEN="$TMP/noop-xcodegen"
readonly NONDETERMINISTIC_XCODEGEN="$TMP/nondeterministic-xcodegen"
failures=0
run_status=0
run_output=""

fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

pass() {
  echo "PASS: $*"
}

write_fake_xcodegen() {
  cat > "$NOOP_XCODEGEN" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
case "${1:-}" in
  --version)
    printf 'Version: %s\n' "${MOCK_XCODEGEN_VERSION:-2.46.0}"
    ;;
  generate)
    printf '%s\n' "$*" >> "${MOCK_XCODEGEN_LOG:-/dev/null}"
    ;;
  *)
    echo "Unexpected fake XcodeGen invocation: $*" >&2
    exit 90
    ;;
esac
EOF

  cat > "$NONDETERMINISTIC_XCODEGEN" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
case "${1:-}" in
  --version)
    printf 'Version: 2.46.0\n'
    ;;
  generate)
    count="$(cat "${MOCK_GENERATION_COUNT:?}")"
    count=$((count + 1))
    printf '%s' "$count" > "$MOCK_GENERATION_COUNT"
    printf '\n' >> "${MOCK_PBXPROJ:?}"
    ;;
  *)
    exit 90
    ;;
esac
EOF
  chmod +x "$NOOP_XCODEGEN" "$NONDETERMINISTIC_XCODEGEN"
}

make_fixture() {
  local name="$1"
  local fixture="$TMP/$name"
  mkdir -p "$fixture/OpenTVTracker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
  mkdir -p "$fixture/OpenTVTracker.xcodeproj/xcshareddata/xcschemes"
  cp "$ROOT/.gitignore" "$fixture/.gitignore"
  cp "$ROOT/project.yml" "$fixture/project.yml"
  cp -R "$ROOT/Config" "$fixture/Config"
  cp "$ROOT/OpenTVTracker.xcodeproj/project.pbxproj" \
    "$fixture/OpenTVTracker.xcodeproj/project.pbxproj"
  cp "$ROOT/OpenTVTracker.xcodeproj/project.xcworkspace/contents.xcworkspacedata" \
    "$fixture/OpenTVTracker.xcodeproj/project.xcworkspace/contents.xcworkspacedata"
  cp "$ROOT/OpenTVTracker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" \
    "$fixture/OpenTVTracker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
  cp "$ROOT/OpenTVTracker.xcodeproj/xcshareddata/xcschemes/OpenTVTracker.xcscheme" \
    "$fixture/OpenTVTracker.xcodeproj/xcshareddata/xcschemes/OpenTVTracker.xcscheme"
  printf '%s\n' "$fixture"
}

initialize_fixture_git() {
  local fixture="$1"
  git -C "$fixture" init -q
  git -C "$fixture" config user.name "OpenTV Test"
  git -C "$fixture" config user.email "test@opentvtracker.invalid"
  git -C "$fixture" add .
  git -C "$fixture" commit -qm "fixture"
}

run_script() {
  local fixture="$1"
  local command="$2"
  local binary="${3:-$NOOP_XCODEGEN}"
  local version="${4:-2.46.0}"
  local log="${5:-$TMP/xcodegen.log}"
  local pbxproj="${6:-$fixture/OpenTVTracker.xcodeproj/project.pbxproj}"
  local count_file="${7:-$TMP/generation-count}"

  : > "$log"
  [[ -f "$count_file" ]] || printf '0' > "$count_file"
  set +e
  run_output="$(
    OPENTV_PROJECT_ROOT="$fixture" \
    OPENTV_XCODEGEN_BIN="$binary" \
    OPENTV_GENERATION_TEST_MODE=1 \
    MOCK_XCODEGEN_VERSION="$version" \
    MOCK_XCODEGEN_LOG="$log" \
    MOCK_PBXPROJ="$pbxproj" \
    MOCK_GENERATION_COUNT="$count_file" \
      "$SCRIPT" "$command" 2>&1
  )"
  run_status=$?
  set -e
}

expect_success() {
  local label="$1"
  local fixture="$2"
  local command="${3:-validate}"
  local binary="${4:-$NOOP_XCODEGEN}"
  run_script "$fixture" "$command" "$binary"
  if (( run_status == 0 )); then
    pass "$label"
  else
    fail "$label returned $run_status: $run_output"
  fi
}

expect_failure() {
  local label="$1"
  local fixture="$2"
  local expected="$3"
  local command="${4:-validate}"
  local binary="${5:-$NOOP_XCODEGEN}"
  local version="${6:-2.46.0}"
  run_script "$fixture" "$command" "$binary" "$version"
  if (( run_status == 0 )); then
    fail "$label unexpectedly succeeded"
  elif [[ "$run_output" != *"$expected"* ]]; then
    fail "$label omitted '$expected': $run_output"
  else
    pass "$label"
  fi
}

rewrite_lock() {
  local fixture="$1"
  local filter="$2"
  local lock="$fixture/OpenTVTracker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
  jq "$filter" "$lock" > "$lock.next"
  mv "$lock.next" "$lock"
}

write_fake_xcodegen

tampered_archive="$TMP/tampered-xcodegen.zip"
printf 'not the official XcodeGen release' > "$tampered_archive"
set +e
run_output="$(bash -c 'source "$1"; verify_xcodegen_archive "$2"' _ "$SCRIPT" "$tampered_archive" 2>&1)"
run_status=$?
set -e
if (( run_status == 0 )); then
  fail "rejects a tampered XcodeGen archive unexpectedly succeeded"
elif [[ "$run_output" != *"XcodeGen archive checksum mismatch"* ]]; then
  fail "rejects a tampered XcodeGen archive omitted the checksum error: $run_output"
else
  pass "rejects a tampered XcodeGen archive"
fi

fixture="$(make_fixture valid-contract)"
expect_success "accepts the exact project, entitlement, and lock contract" "$fixture"

fixture="$(make_fixture ranged-package)"
perl -0pi -e 's/exactVersion: 0\.9\.20/from: 0.9.20/' "$fixture/project.yml"
expect_failure "rejects a ranged package requirement" "$fixture" "exactVersion: 0.9.20"

fixture="$(make_fixture project-system-capabilities)"
printf '\n# SystemCapabilities\n' >> "$fixture/project.yml"
expect_failure "rejects SystemCapabilities in project.yml" "$fixture" "must not emit XcodeGen's malformed SystemCapabilities"

fixture="$(make_fixture generated-system-capabilities)"
printf '\nSystemCapabilities = "malformed";\n' >> "$fixture/OpenTVTracker.xcodeproj/project.pbxproj"
expect_failure "rejects malformed generated SystemCapabilities" "$fixture" "Generated project contains SystemCapabilities"

fixture="$(make_fixture generated-version-range)"
perl -0pi -e 's/kind = exactVersion;/kind = upToNextMajorVersion;/' "$fixture/OpenTVTracker.xcodeproj/project.pbxproj"
expect_failure "rejects a generated package version range" "$fixture" "one exact Swift package requirement"

fixture="$(make_fixture missing-lock)"
rm "$fixture/OpenTVTracker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
expect_failure "rejects a missing shared lockfile" "$fixture" "Required file is missing"

fixture="$(make_fixture malformed-lock)"
printf '{not-json' > "$fixture/OpenTVTracker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
expect_failure "rejects a malformed shared lockfile" "$fixture" "Package.resolved must contain only ZIPFoundation"

fixture="$(make_fixture extra-pin)"
rewrite_lock "$fixture" '.pins += [.pins[0]]'
expect_failure "rejects an extra package pin" "$fixture" "must contain only ZIPFoundation"

fixture="$(make_fixture wrong-location)"
rewrite_lock "$fixture" '.pins[0].location = "https://attacker.invalid/ZIPFoundation"'
expect_failure "rejects a noncanonical package location" "$fixture" "must contain only ZIPFoundation"

fixture="$(make_fixture wrong-version)"
rewrite_lock "$fixture" '.pins[0].state.version = "0.9.21"'
expect_failure "rejects a different package version" "$fixture" "must contain only ZIPFoundation"

fixture="$(make_fixture wrong-revision)"
rewrite_lock "$fixture" '.pins[0].state.revision = "0000000000000000000000000000000000000000"'
expect_failure "rejects a different package revision" "$fixture" "must contain only ZIPFoundation"

fixture="$(make_fixture wrong-origin-hash)"
rewrite_lock "$fixture" '.originHash = "not-a-sha256"'
expect_failure "rejects a malformed package origin hash" "$fixture" "must contain only ZIPFoundation"

fixture="$(make_fixture missing-app-entitlement)"
/usr/libexec/PlistBuddy -c 'Delete :aps-environment' "$fixture/Config/OpenTVTracker.entitlements"
expect_failure "rejects a missing app entitlement" "$fixture" "authoritative app capability contract"

fixture="$(make_fixture extra-app-entitlement)"
/usr/libexec/PlistBuddy -c 'Add :unexpected-capability string enabled' "$fixture/Config/OpenTVTracker.entitlements"
expect_failure "rejects an undeclared app entitlement" "$fixture" "authoritative app capability contract"

fixture="$(make_fixture wrong-app-entitlement)"
/usr/libexec/PlistBuddy -c 'Set :aps-environment production' "$fixture/Config/OpenTVTracker.entitlements"
expect_failure "rejects a changed app entitlement value" "$fixture" "authoritative app capability contract"

fixture="$(make_fixture wrong-widget-entitlement)"
/usr/libexec/PlistBuddy -c 'Set :com.apple.security.application-groups:0 group.attacker.invalid' "$fixture/Config/OpenTVWidgets.entitlements"
expect_failure "rejects a changed widget entitlement value" "$fixture" "authoritative widget capability contract"

fixture="$(make_fixture missing-build-setting)"
perl -0pi -e 's/APP_ATTEST_ENVIRONMENT: production/APP_ATTEST_ENVIRONMENT: staging/' "$fixture/project.yml"
expect_failure "rejects missing production capability build settings" "$fixture" "production App Attest environment"

fixture="$(make_fixture wrong-xcodegen-version)"
expect_failure "rejects a different XcodeGen version" "$fixture" "Expected XcodeGen 2.46.0" generate "$NOOP_XCODEGEN" "2.45.4"

fixture="$(make_fixture production-generator-override)"
set +e
run_output="$(
  OPENTV_PROJECT_ROOT="$fixture" \
  OPENTV_XCODEGEN_BIN="$NOOP_XCODEGEN" \
    "$SCRIPT" generate 2>&1
)"
run_status=$?
set -e
if (( run_status == 0 )); then
  fail "rejects a production generator override unexpectedly succeeded"
elif [[ "$run_output" != *"reserved for the isolated helper test harness"* ]]; then
  fail "rejects a production generator override omitted the isolation error: $run_output"
else
  pass "rejects a production generator override"
fi

fixture="$(make_fixture pinned-generator-arguments)"
generator_log="$TMP/pinned-generator.log"
run_script "$fixture" generate "$NOOP_XCODEGEN" "2.46.0" "$generator_log"
if (( run_status != 0 )); then
  fail "invokes the pinned generator returned $run_status: $run_output"
elif ! grep -Fq -- '--no-env' "$generator_log" \
  || ! grep -Fq -- "--spec $fixture/project.yml" "$generator_log" \
  || ! grep -Fq -- "--project $fixture" "$generator_log" \
  || ! grep -Fq -- "--project-root $fixture" "$generator_log"
then
  fail "invokes the pinned generator with deterministic paths and --no-env: $(cat "$generator_log")"
else
  pass "invokes the pinned generator with deterministic paths and --no-env"
fi

fixture="$(make_fixture clean-check)"
initialize_fixture_git "$fixture"
clean_log="$TMP/clean-check.log"
run_script "$fixture" check "$NOOP_XCODEGEN" "2.46.0" "$clean_log"
if (( run_status != 0 )); then
  fail "accepts two byte-identical clean generations returned $run_status: $run_output"
elif [[ "$(grep -c '^generate ' "$clean_log")" != "2" ]]; then
  fail "clean check did not invoke XcodeGen exactly twice: $(cat "$clean_log")"
else
  pass "accepts two byte-identical clean generations"
fi

fixture="$(make_fixture committed-drift)"
initialize_fixture_git "$fixture"
printf '\n' >> "$fixture/OpenTVTracker.xcodeproj/project.pbxproj"
expect_failure "rejects committed-project drift" "$fixture" "differs from the committed files" check

fixture="$(make_fixture nondeterministic-generation)"
initialize_fixture_git "$fixture"
count_file="$TMP/nondeterministic-count"
printf '0' > "$count_file"
run_script "$fixture" check "$NONDETERMINISTIC_XCODEGEN" "2.46.0" \
  "$TMP/nondeterministic.log" \
  "$fixture/OpenTVTracker.xcodeproj/project.pbxproj" \
  "$count_file"
if (( run_status == 0 )); then
  fail "rejects byte-unstable generation unexpectedly succeeded"
elif [[ "$run_output" != *"Two clean XcodeGen runs were not byte-stable"* ]]; then
  fail "rejects byte-unstable generation omitted the stability error: $run_output"
else
  pass "rejects byte-unstable generation"
fi

if [[ "$(grep -Fc 'build-and-test:' "$ROOT/.github/workflows/ios.yml")" != "1" ]] \
  || [[ "$(grep -Fc 'name: build-and-test' "$ROOT/.github/workflows/ios.yml")" != "1" ]]
then
  fail "iOS workflow must preserve the exact build-and-test job/check name"
elif [[ "$(grep -Fc -- '-onlyUsePackageVersionsFromResolvedFile' "$ROOT/.github/workflows/ios.yml")" != "2" ]] \
  || [[ "$(grep -Fc -- '-disableAutomaticPackageResolution' "$ROOT/.github/workflows/ios.yml")" != "2" ]] \
  || grep -Eq -- '-skipPackage(SignatureValidation|PluginValidation)' "$ROOT/.github/workflows/ios.yml"
then
  fail "iOS workflow must lock resolution without weakening package validation"
else
  pass "iOS workflow preserves the release check and fails closed on package resolution"
fi

if (( failures > 0 )); then
  echo "$failures assertion(s) failed" >&2
  exit 1
fi
echo "All reproducible iOS generation assertions passed."
