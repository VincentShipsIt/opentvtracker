#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

readonly SHA="0123456789abcdef0123456789abcdef01234567"
readonly IMAGE_KEY="images/api-opentvtracker-dev-${SHA}.tar.gz"
readonly PARAMETER_PATH="/shipshit/production/opentvtracker/"
readonly MOCK_BIN="${TMP}/bin"
readonly BASE_PARAMETERS="${TMP}/base-parameters.json"
readonly PARAMETERS="${TMP}/parameters.json"
readonly CAPTURED_ENVIRONMENT="${TMP}/captured-production.env"
readonly INSTALL_LOG="${TMP}/install.log"
readonly DOCKER_LOG="${TMP}/docker.log"
readonly STDOUT_LOG="${TMP}/stdout.log"
readonly STDERR_LOG="${TMP}/stderr.log"

failures=0
run_status=0

fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

pass() {
  echo "PASS: $*"
}

write_mocks() {
  mkdir -p "$MOCK_BIN"

  cat >"${MOCK_BIN}/aws" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "${1:-}" == "ssm" && "${2:-}" == "get-parameters-by-path" ]]; then
  /bin/cat "${MOCK_SSM_PARAMETERS:?}"
  exit 0
fi
if [[ "${1:-}" == "s3" && "${2:-}" == "cp" ]]; then
  : >"${4:?}"
  exit 0
fi
echo "Unexpected aws invocation" >&2
exit 90
EOF

  cat >"${MOCK_BIN}/install" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${MOCK_INSTALL_LOG:?}"
if [[ "${1:-}" == "-d" ]]; then
  exit 0
fi
if [[ "${1:-}" == "-m" && "${2:-}" == "600" ]]; then
  /bin/cp "${3:?}" "${MOCK_CAPTURED_ENVIRONMENT:?}"
  exit 0
fi
echo "Unexpected install invocation" >&2
exit 90
EOF

  cat >"${MOCK_BIN}/mktemp" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
case "${1:-}" in
  *production.env*) destination="${MOCK_TEMP_ROOT:?}/production.env.tmp" ;;
  *api-opentvtracker-dev*) destination="${MOCK_TEMP_ROOT:?}/artifact.tar.gz" ;;
  *) echo "Unexpected mktemp template" >&2; exit 90 ;;
esac
: >"$destination"
printf '%s\n' "$destination"
EOF

  cat >"${MOCK_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${MOCK_DOCKER_LOG:?}"
if [[ "${1:-}" == "run" ]]; then
  printf 'mock-container-id\n'
elif [[ "${1:-}" == "inspect" && "${2:-}" == "--format" ]]; then
  printf 'healthy\n'
fi
EOF

  cat >"${MOCK_BIN}/gzip" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  cat >"${MOCK_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  cat >"${MOCK_BIN}/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  chmod +x "${MOCK_BIN}/"*
}

write_base_parameters() {
  cat >"$BASE_PARAMETERS" <<JSON
[
  ["${PARAMETER_PATH}DATABASE_URL", "postgresql://test:test@database.test:5432/opentv?sslmode=require"],
  ["${PARAMETER_PATH}APP_ATTEST_MODE", "production"],
  ["${PARAMETER_PATH}APP_ATTEST_TEAM_ID", "TESTTEAM01"],
  ["${PARAMETER_PATH}APP_ATTEST_BUNDLE_ID", "dev.opentvtracker.test"],
  ["${PARAMETER_PATH}APP_ATTEST_TOKEN_SECRET", "test-only-token-secret-at-least-32-characters"],
  ["${PARAMETER_PATH}TMDB_READ_ACCESS_TOKEN", "test-only-read-token"],
  ["${PARAMETER_PATH}CORS_ALLOWED_ORIGIN", "https://example.test/path?first=one=two"]
]
JSON
}

reset_case() {
  : >"$INSTALL_LOG"
  : >"$DOCKER_LOG"
  : >"$STDOUT_LOG"
  : >"$STDERR_LOG"
  rm -f "$CAPTURED_ENVIRONMENT"
}

run_deploy() {
  reset_case
  set +e
  PATH="${MOCK_BIN}:$PATH" \
    MOCK_SSM_PARAMETERS="$PARAMETERS" \
    MOCK_CAPTURED_ENVIRONMENT="$CAPTURED_ENVIRONMENT" \
    MOCK_INSTALL_LOG="$INSTALL_LOG" \
    MOCK_DOCKER_LOG="$DOCKER_LOG" \
    MOCK_TEMP_ROOT="$TMP" \
    bash "$ROOT/deploy/aws/deploy-opentvtracker.sh" "$IMAGE_KEY" "$SHA" \
      >"$STDOUT_LOG" 2>"$STDERR_LOG"
  run_status=$?
  set -e
}

expect_rejected_before_install() {
  local label="$1"
  local expected_error="$2"
  if (( run_status == 0 )); then
    fail "$label should fail"
    return
  fi
  if ! grep -Fq "$expected_error" "$STDERR_LOG"; then
    fail "$label returned the wrong error: $(cat "$STDERR_LOG")"
    return
  fi
  if grep -Fq -- "-m 600" "$INSTALL_LOG"; then
    fail "$label installed a Docker environment file"
    return
  fi
  if [[ -s "$DOCKER_LOG" ]]; then
    fail "$label reached Docker"
    return
  fi
  pass "$label is rejected before environment installation or Docker"
}

write_mocks
write_base_parameters

cp "$BASE_PARAMETERS" "$PARAMETERS"
run_deploy
if (( run_status != 0 )); then
  fail "valid production parameters should deploy through the mocked harness: $(cat "$STDERR_LOG")"
elif [[ ! -f "$CAPTURED_ENVIRONMENT" ]]; then
  fail "valid production parameters did not install the environment file"
elif ! grep -Fxq "APP_ATTEST_MODE=production" "$CAPTURED_ENVIRONMENT" \
  || ! grep -Fxq "NODE_ENV=production" "$CAPTURED_ENVIRONMENT" \
  || ! grep -Fxq "CORS_ALLOWED_ORIGIN=https://example.test/path?first=one=two" "$CAPTURED_ENVIRONMENT"
then
  fail "valid production parameters were not preserved exactly"
else
  pass "valid production parameters are installed exactly"
fi

for mode in development test "production "; do
  jq --arg mode "$mode" --arg key "${PARAMETER_PATH}APP_ATTEST_MODE" \
    'map(if .[0] == $key then .[1] = $mode else . end)' \
    "$BASE_PARAMETERS" >"$PARAMETERS"
  run_deploy
  expect_rejected_before_install \
    "APP_ATTEST_MODE=$(printf '%q' "$mode")" \
    "APP_ATTEST_MODE must be exactly production for deployment"
done

jq --arg key "${PARAMETER_PATH}APP_ATTEST_DEVELOPMENT_BYPASS_TOKEN" \
  '. + [[$key, ""]]' "$BASE_PARAMETERS" >"$PARAMETERS"
run_deploy
expect_rejected_before_install \
  "an empty development bypass parameter" \
  "APP_ATTEST_DEVELOPMENT_BYPASS_TOKEN is forbidden in production deployment"

for separator in lf trailing-lf cr; do
  case "$separator" in
    lf)
      injected_value=$'test-only-read-token\n'"${PARAMETER_PATH}"$'APP_ATTEST_DEVELOPMENT_BYPASS_TOKEN\tinjected-value'
      ;;
    trailing-lf)
      injected_value=$'test-only-read-token\n'
      ;;
    cr)
      injected_value=$'test-only-read-token\rAPP_ATTEST_MODE=development'
      ;;
  esac
  jq --arg value "$injected_value" --arg key "${PARAMETER_PATH}TMDB_READ_ACCESS_TOKEN" \
    'map(if .[0] == $key then .[1] = $value else . end)' \
    "$BASE_PARAMETERS" >"$PARAMETERS"
  run_deploy
  expect_rejected_before_install \
    "an SSM value containing ${separator^^}" \
    "SSM values must not contain NUL, CR, or LF"
  if grep -Fq "injected-value" "$STDERR_LOG"; then
    fail "the ${separator^^} rejection logged the rejected value"
  fi
done

for nul_case in mode credential; do
  case "$nul_case" in
    mode)
      nul_key="${PARAMETER_PATH}APP_ATTEST_MODE"
      nul_prefix="pro"
      nul_suffix="duction"
      ;;
    credential)
      nul_key="${PARAMETER_PATH}TMDB_READ_ACCESS_TOKEN"
      nul_prefix="test-only-read"
      nul_suffix="-token"
      ;;
  esac
  jq \
    --arg key "$nul_key" \
    --arg prefix "$nul_prefix" \
    --arg suffix "$nul_suffix" \
    'map(if .[0] == $key then .[1] = ($prefix + "\u0000" + $suffix) else . end)' \
    "$BASE_PARAMETERS" >"$PARAMETERS"
  run_deploy
  expect_rejected_before_install \
    "a NUL byte in the ${nul_case} SSM value" \
    "SSM values must not contain NUL, CR, or LF"
done

jq --arg key "${PARAMETER_PATH}APP_ATTEST_TEAM_ID" \
  '. + [[$key, "DUPLICATE"]]' "$BASE_PARAMETERS" >"$PARAMETERS"
run_deploy
expect_rejected_before_install \
  "duplicate SSM parameter leaves" \
  "Duplicate SSM parameter leaf: APP_ATTEST_TEAM_ID"

jq --arg key "${PARAMETER_PATH}TMDB_READ_ACCESS_TOKEN" \
  'map(if .[0] == $key then .[1] = 42 else . end)' \
  "$BASE_PARAMETERS" >"$PARAMETERS"
run_deploy
expect_rejected_before_install \
  "a non-string SSM value" \
  "SSM response must contain string name/value pairs"

if (( failures > 0 )); then
  echo "$failures assertion(s) failed" >&2
  exit 1
fi
echo "All OpenTV deployment assertions passed."
