#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
readonly ROOT
readonly SCRIPT="$ROOT/.github/scripts/run-swiftlint.sh"

TMP="$(mktemp -d)"
readonly TMP
trap 'rm -rf "$TMP"' EXIT

readonly FAKE_SWIFTLINT="$TMP/swiftlint"
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

run_script() {
  local version="${1:-0.65.0}"
  local exit_status="${2:-0}"
  : > "$TMP/invocations"
  set +e
  run_output="$(
    OPENTV_SWIFTLINT_ROOT="$ROOT" \
    OPENTV_SWIFTLINT_BIN="$FAKE_SWIFTLINT" \
    OPENTV_SWIFTLINT_TEST_MODE=1 \
    MOCK_SWIFTLINT_VERSION="$version" \
    MOCK_SWIFTLINT_EXIT_STATUS="$exit_status" \
    MOCK_SWIFTLINT_LOG="$TMP/invocations" \
      "$SCRIPT" 2>&1
  )"
  run_status=$?
  set -e
}

cat > "$FAKE_SWIFTLINT" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
case "${1:-}" in
  version)
    printf '%s\n' "${MOCK_SWIFTLINT_VERSION:-0.65.0}"
    ;;
  lint)
    printf '%s\n' "$*" >> "${MOCK_SWIFTLINT_LOG:?}"
    exit "${MOCK_SWIFTLINT_EXIT_STATUS:-0}"
    ;;
  *)
    echo "Unexpected fake SwiftLint invocation: $*" >&2
    exit 90
    ;;
esac
EOF
chmod +x "$FAKE_SWIFTLINT"

run_script
if (( run_status != 0 )); then
  fail "accepts the pinned SwiftLint version returned $run_status: $run_output"
elif [[ "$(<"$TMP/invocations")" != "lint --strict --no-cache" ]]; then
  fail "passes the exact strict/no-cache arguments: $(<"$TMP/invocations")"
else
  pass "accepts the pinned version and passes the exact lint arguments"
fi

run_script "0.64.0"
if (( run_status == 0 )); then
  fail "rejects a different SwiftLint version unexpectedly succeeded"
elif [[ "$run_output" != *"Expected SwiftLint 0.65.0"* ]]; then
  fail "rejects a different SwiftLint version omitted the version diagnostic: $run_output"
else
  pass "rejects a different SwiftLint version"
fi

run_script "0.65.0" 7
if [[ "$run_status" != "7" ]]; then
  fail "propagates SwiftLint violations expected 7, got $run_status: $run_output"
else
  pass "propagates SwiftLint violations"
fi

set +e
run_output="$(OPENTV_SWIFTLINT_BIN="$FAKE_SWIFTLINT" "$SCRIPT" 2>&1)"
run_status=$?
set -e
if (( run_status == 0 )); then
  fail "rejects a production binary override unexpectedly succeeded"
elif [[ "$run_output" != *"reserved for the isolated helper test harness"* ]]; then
  fail "rejects a production binary override omitted the override diagnostic: $run_output"
else
  pass "rejects a production binary override"
fi

tampered_archive="$TMP/tampered-swiftlint.zip"
printf 'not the official SwiftLint release' > "$tampered_archive"
set +e
run_output="$(bash -c 'source "$1"; verify_swiftlint_archive "$2"' _ "$SCRIPT" "$tampered_archive" 2>&1)"
run_status=$?
set -e
if (( run_status == 0 )); then
  fail "rejects a tampered SwiftLint archive unexpectedly succeeded"
elif [[ "$run_output" != *"SwiftLint archive checksum mismatch"* ]]; then
  fail "rejects a tampered SwiftLint archive omitted the checksum diagnostic: $run_output"
else
  pass "rejects a tampered SwiftLint archive"
fi

if (( failures > 0 )); then
  echo "$failures assertion(s) failed" >&2
  exit 1
fi
echo "All pinned SwiftLint entrypoint assertions passed."
