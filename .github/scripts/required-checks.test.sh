#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REQUIRED_CHECKS_TIMEOUT_SECONDS=0
REQUIRED_CHECKS_POLL_INTERVAL_SECONDS=1
# shellcheck source=required-checks.sh
source "$ROOT/.github/scripts/required-checks.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
readonly SHA='0123456789abcdef0123456789abcdef01234567'
readonly WRONG_SHA='abcdefabcdefabcdefabcdefabcdefabcdefabcd'
readonly SUCCESS_FIXTURE="$TMP/success.json"
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

write_success_fixture() {
  jq -n --arg sha "$SHA" '
    def workflow($id; $number; $suite; $path): {
      id: $id,
      run_number: $number,
      run_attempt: 1,
      check_suite_id: $suite,
      path: $path,
      event: "push",
      head_branch: "main",
      head_sha: $sha,
      status: "completed",
      conclusion: "success",
      html_url: ("https://example.test/actions/runs/" + ($id | tostring))
    };
    def check($id; $suite; $name): {
      id: $id,
      name: $name,
      head_sha: $sha,
      status: "completed",
      conclusion: "success",
      started_at: "2026-08-23T10:00:00Z",
      completed_at: "2026-08-23T10:01:00Z",
      details_url: ("https://example.test/checks/" + ($id | tostring)),
      app: {slug: "github-actions"},
      check_suite: {id: $suite}
    };
    {
      source_sha: $sha,
      contracts: [
        {
          workflow_path: ".github/workflows/ios.yml",
          check_name: "build-and-test",
          workflow_run: workflow(1001; 11; 2001; ".github/workflows/ios.yml"),
          check_runs: [check(3001; 2001; "build-and-test")]
        },
        {
          workflow_path: ".github/workflows/server.yml",
          check_name: "test-and-typecheck",
          workflow_run: workflow(1002; 12; 2002; ".github/workflows/server.yml"),
          check_runs: [check(3002; 2002; "test-and-typecheck")]
        },
        {
          workflow_path: ".github/workflows/secret-scan.yml",
          check_name: "gitleaks",
          workflow_run: workflow(1003; 13; 2003; ".github/workflows/secret-scan.yml"),
          check_runs: [check(3003; 2003; "gitleaks")]
        }
      ]
    }
  ' > "$SUCCESS_FIXTURE"
}

evaluate_fixture() {
  local fixture="$1"
  set +e
  run_output="$(required_checks_evaluate_snapshot "$SHA" "$fixture" 2>&1)"
  run_status=$?
  set -e
}

expect_fixture() {
  local label="$1"
  local fixture="$2"
  local expected_status="$3"
  local expected_text="$4"
  evaluate_fixture "$fixture"
  if (( run_status != expected_status )); then
    fail "$label returned $run_status instead of $expected_status: $run_output"
  elif [[ "$run_output" != *"$expected_text"* ]]; then
    fail "$label omitted '$expected_text': $run_output"
  else
    pass "$label"
  fi
}

write_mock_curl() {
  local mock_bin="$TMP/mock-bin"
  mkdir -p "$mock_bin"
  cat > "$mock_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
output=""
url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      output="$2"
      shift 2
      ;;
    -H|--connect-timeout|--max-time|--retry)
      shift 2
      ;;
    --fail-with-body|--location|--silent|--show-error|--retry-all-errors)
      shift
      ;;
    http://*|https://*)
      url="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done
printf '%s\n' "$url" >> "${MOCK_CURL_LOG:?}"
if [[ "${MOCK_CURL_EXIT:-0}" != "0" ]]; then
  exit "$MOCK_CURL_EXIT"
fi

write_runs() {
  local path="$1"
  local run_id="$2"
  local run_number="$3"
  local suite_id="$4"
  jq -n \
    --arg sha "${MOCK_SHA:?}" \
    --arg path "$path" \
    --argjson run_id "$run_id" \
    --argjson run_number "$run_number" \
    --argjson suite_id "$suite_id" '
    {
      total_count: 2,
      workflow_runs: [
        {
          id: 9999,
          run_number: 999,
          run_attempt: 1,
          check_suite_id: 9999,
          path: $path,
          event: "workflow_dispatch",
          head_branch: "main",
          head_sha: $sha,
          status: "completed",
          conclusion: "success"
        },
        {
          id: $run_id,
          run_number: $run_number,
          run_attempt: 2,
          check_suite_id: $suite_id,
          path: $path,
          event: "push",
          head_branch: "main",
          head_sha: $sha,
          status: "completed",
          conclusion: "success"
        }
      ]
    }
  ' > "$output"
}

write_checks() {
  local suite_id="$1"
  local check_id="$2"
  local name="$3"
  jq -n \
    --arg sha "${MOCK_SHA:?}" \
    --arg name "$name" \
    --argjson suite_id "$suite_id" \
    --argjson check_id "$check_id" '
    {
      total_count: 1,
      check_runs: [{
        id: $check_id,
        name: $name,
        head_sha: $sha,
        status: "completed",
        conclusion: "success",
        started_at: "2026-08-23T10:00:00Z",
        completed_at: "2026-08-23T10:01:00Z",
        details_url: "https://example.test/check",
        app: {slug: "github-actions"},
        check_suite: {id: $suite_id}
      }]
    }
  ' > "$output"
}

case "$url" in
  */actions/workflows/ios.yml/runs*)
    write_runs '.github/workflows/ios.yml' 1001 11 2001
    ;;
  */actions/workflows/server.yml/runs*)
    write_runs '.github/workflows/server.yml' 1002 12 2002
    ;;
  */actions/workflows/secret-scan.yml/runs*)
    write_runs '.github/workflows/secret-scan.yml' 1003 13 2003
    ;;
  */check-suites/2001/check-runs*)
    write_checks 2001 3001 build-and-test
    ;;
  */check-suites/2002/check-runs*)
    write_checks 2002 3002 test-and-typecheck
    ;;
  */check-suites/2003/check-runs*)
    write_checks 2003 3003 gitleaks
    ;;
  *)
    echo "Unexpected mock URL: $url" >&2
    exit 90
    ;;
esac
EOF
  chmod +x "$mock_bin/curl"
  printf '%s' "$mock_bin"
}

write_success_fixture

expect_fixture \
  "three exact successful checks pass" \
  "$SUCCESS_FIXTURE" \
  0 \
  "Check gitleaks"

reversed_fixture="$TMP/reversed.json"
jq '.contracts |= reverse | .contracts[].check_runs |= reverse' \
  "$SUCCESS_FIXTURE" > "$reversed_fixture"
expect_fixture \
  "fixture order does not affect success" \
  "$reversed_fixture" \
  0 \
  "Check build-and-test"

for status in queued in_progress requested waiting pending; do
  pending_fixture="$TMP/pending-${status}.json"
  jq --arg status "$status" '
    .contracts[0].workflow_run.status = $status |
    .contracts[0].workflow_run.conclusion = null |
    .contracts[0].check_runs[0].status = $status |
    .contracts[0].check_runs[0].conclusion = null
  ' "$SUCCESS_FIXTURE" > "$pending_fixture"
  expect_fixture \
    "nonterminal status $status remains pending" \
    "$pending_fixture" \
    "$REQUIRED_CHECKS_PENDING" \
    "status=$status conclusion=null"
done

missing_fixture="$TMP/missing.json"
jq '.contracts[0].workflow_run = null | .contracts[0].check_runs = []' \
  "$SUCCESS_FIXTURE" > "$missing_fixture"
expect_fixture \
  "missing push suite cannot satisfy the gate" \
  "$missing_fixture" \
  "$REQUIRED_CHECKS_MISSING" \
  "has appeared"

completed_missing_fixture="$TMP/completed-missing.json"
jq '.contracts[0].check_runs = []' \
  "$SUCCESS_FIXTURE" > "$completed_missing_fixture"
expect_fixture \
  "completed suite with a missing check fails immediately" \
  "$completed_missing_fixture" \
  "$REQUIRED_CHECKS_FAILED" \
  "is missing exact check"

for conclusion in failure cancelled skipped neutral stale timed_out action_required; do
  terminal_fixture="$TMP/terminal-${conclusion}.json"
  jq --arg conclusion "$conclusion" \
    '.contracts[0].check_runs[0].conclusion = $conclusion' \
    "$SUCCESS_FIXTURE" > "$terminal_fixture"
  expect_fixture \
    "terminal conclusion $conclusion fails closed" \
    "$terminal_fixture" \
    "$REQUIRED_CHECKS_FAILED" \
    "conclusion=$conclusion"
done

null_conclusion_fixture="$TMP/terminal-null.json"
jq '.contracts[0].check_runs[0].conclusion = null' \
  "$SUCCESS_FIXTURE" > "$null_conclusion_fixture"
expect_fixture \
  "completed check with no conclusion fails closed" \
  "$null_conclusion_fixture" \
  "$REQUIRED_CHECKS_FAILED" \
  "conclusion=null"

wrong_sha_fixture="$TMP/wrong-sha.json"
jq --arg wrong_sha "$WRONG_SHA" \
  '.contracts[0].check_runs[0].head_sha = $wrong_sha' \
  "$SUCCESS_FIXTURE" > "$wrong_sha_fixture"
expect_fixture \
  "wrong-SHA check cannot satisfy the gate" \
  "$wrong_sha_fixture" \
  "$REQUIRED_CHECKS_FAILED" \
  "is missing exact check"

wrong_name_fixture="$TMP/wrong-name.json"
jq '.contracts[0].check_runs[0].name = "Build-and-test"' \
  "$SUCCESS_FIXTURE" > "$wrong_name_fixture"
expect_fixture \
  "wrong-name check cannot satisfy the gate" \
  "$wrong_name_fixture" \
  "$REQUIRED_CHECKS_FAILED" \
  "name=Build-and-test"

wrong_provenance_fixture="$TMP/wrong-provenance.json"
jq '.contracts[0].workflow_run.event = "workflow_dispatch"' \
  "$SUCCESS_FIXTURE" > "$wrong_provenance_fixture"
expect_fixture \
  "manual-dispatch provenance cannot satisfy the gate" \
  "$wrong_provenance_fixture" \
  "$REQUIRED_CHECKS_FAILED" \
  "provenance does not match"

duplicate_fixture="$TMP/duplicate.json"
jq '.contracts[0].check_runs += [(.contracts[0].check_runs[0] | .id = 3999)]' \
  "$SUCCESS_FIXTURE" > "$duplicate_fixture"
expect_fixture \
  "duplicate latest exact-name checks fail closed" \
  "$duplicate_fixture" \
  "$REQUIRED_CHECKS_FAILED" \
  "refusing ambiguity"

rerun_success_fixture="$TMP/rerun-success.json"
jq '
  .contracts[0].workflow_run.run_attempt = 2 |
  .contracts[0].check_runs[0].id = 4001 |
  .contracts[0].check_runs[0].conclusion = "success"
' "$SUCCESS_FIXTURE" > "$rerun_success_fixture"
expect_fixture \
  "latest successful rerun passes" \
  "$rerun_success_fixture" \
  0 \
  "attempt=2"

rerun_failure_fixture="$TMP/rerun-failure.json"
jq '
  .contracts[0].workflow_run.run_attempt = 2 |
  .contracts[0].workflow_run.conclusion = "failure" |
  .contracts[0].check_runs[0].id = 4002 |
  .contracts[0].check_runs[0].conclusion = "failure"
' "$SUCCESS_FIXTURE" > "$rerun_failure_fixture"
expect_fixture \
  "latest failed rerun overrides earlier success" \
  "$rerun_failure_fixture" \
  "$REQUIRED_CHECKS_FAILED" \
  "run=4002"

rerun_pending_old_success_fixture="$TMP/rerun-pending-old-success.json"
jq '
  .contracts[0].workflow_run.run_attempt = 2 |
  .contracts[0].workflow_run.status = "in_progress" |
  .contracts[0].workflow_run.conclusion = null
' "$SUCCESS_FIXTURE" > "$rerun_pending_old_success_fixture"
expect_fixture \
  "in-progress rerun cannot reuse the previous attempt's visible success" \
  "$rerun_pending_old_success_fixture" \
  "$REQUIRED_CHECKS_PENDING" \
  "cannot pass until the suite completes"

partial_rerun_fixture="$TMP/partial-rerun.json"
jq '
  .contracts[2].workflow_run.run_attempt = 2 |
  .contracts[2].workflow_run.conclusion = "failure" |
  .contracts[2].check_runs += [{
    id: 4999,
    name: "Workflow syntax",
    head_sha: .source_sha,
    status: "completed",
    conclusion: "failure",
    app: {slug: "github-actions"},
    check_suite: {id: 2003}
  }]
' "$SUCCESS_FIXTURE" > "$partial_rerun_fixture"
expect_fixture \
  "partial rerun preserves the latest required check in its suite" \
  "$partial_rerun_fixture" \
  0 \
  "Check gitleaks"

malformed_fixture="$TMP/malformed.json"
printf '%s\n' '{"source_sha":"not-the-requested-sha"}' > "$malformed_fixture"
expect_fixture \
  "malformed metadata fails closed" \
  "$malformed_fixture" \
  "$REQUIRED_CHECKS_INVALID" \
  "malformed gate metadata"

runs_fixture="$TMP/multiple-runs.json"
jq -n --arg sha "$SHA" '{items: [
  {
    id: 501,
    run_number: 20,
    run_attempt: 1,
    check_suite_id: 601,
    path: ".github/workflows/ios.yml",
    event: "push",
    head_branch: "main",
    head_sha: $sha,
    status: "completed"
  },
  {
    id: 502,
    run_number: 21,
    run_attempt: 1,
    check_suite_id: 602,
    path: ".github/workflows/ios.yml",
    event: "push",
    head_branch: "main",
    head_sha: $sha,
    status: "completed"
  },
  {
    id: 999,
    run_number: 99,
    run_attempt: 1,
    check_suite_id: 999,
    path: ".github/workflows/ios.yml",
    event: "workflow_dispatch",
    head_branch: "main",
    head_sha: $sha,
    status: "completed"
  }
]}' > "$runs_fixture"
selected_run="$TMP/selected-run.json"
if ! required_checks_select_workflow_run \
  "$SHA" \
  '.github/workflows/ios.yml' \
  "$runs_fixture" \
  "$selected_run"
then
  fail "newest push workflow run should be selectable"
elif [[ "$(jq -r '.id' "$selected_run")" != "502" ]]; then
  fail "workflow selection did not choose the newest push run"
else
  pass "newest push run is deterministic and manual dispatch is ignored"
fi

mock_bin="$(write_mock_curl)"
mock_log="$TMP/curl.log"
: > "$mock_log"
export MOCK_CURL_LOG="$mock_log"
export MOCK_SHA="$SHA"
export GITHUB_REPOSITORY='VincentShipsIt/opentvtracker'
export GITHUB_TOKEN='test-token'
fetched_snapshot="$TMP/fetched.json"
if ! PATH="$mock_bin:$PATH" required_checks_fetch_snapshot "$SHA" "$fetched_snapshot"; then
  fail "mocked GitHub metadata fetch should succeed"
else
  expect_fixture \
    "mocked fetch binds checks to push workflow suites" \
    "$fetched_snapshot" \
    0 \
    "Check test-and-typecheck"
  if ! grep -Fq "event=push" "$mock_log" \
    || ! grep -Fq "branch=main" "$mock_log" \
    || ! grep -Fq "head_sha=$SHA" "$mock_log" \
    || ! grep -Fq "check-runs?filter=latest" "$mock_log"
  then
    fail "GitHub fetch omitted exact provenance or latest-rerun filters: $(cat "$mock_log")"
  else
    pass "GitHub fetch requests exact push provenance and latest suite reruns"
  fi
fi

MOCK_CURL_EXIT=22
export MOCK_CURL_EXIT
if PATH="$mock_bin:$PATH" required_checks_fetch_snapshot "$SHA" "$TMP/api-failure.json" >/dev/null 2>&1; then
  fail "GitHub API failure should fail closed"
else
  pass "GitHub API failure fails closed"
fi
unset MOCK_CURL_EXIT

POLL_FIXTURE="$TMP/poll-fixture.json"
cp "$TMP/pending-in_progress.json" "$POLL_FIXTURE"
required_checks_fetch_snapshot() {
  cp "$POLL_FIXTURE" "$2"
}
set +e
run_output="$(required_checks_wait "$SHA" 2>&1)"
run_status=$?
set -e
if (( run_status == 0 )); then
  fail "pending checks should not pass at the timeout"
elif [[ "$run_output" != *"Timed out after 0s"* \
  || "$run_output" != *"status=in_progress"* ]]; then
  fail "pending timeout omitted its bound or diagnostics: $run_output"
else
  pass "pending checks time out with a bounded diagnostic"
fi

cp "$missing_fixture" "$POLL_FIXTURE"
set +e
run_output="$(required_checks_wait "$SHA" 2>&1)"
run_status=$?
set -e
if (( run_status == 0 )); then
  fail "missing suites should not pass at the timeout"
elif [[ "$run_output" != *"Timed out after 0s"* \
  || "$run_output" != *"has appeared"* ]]; then
  fail "missing timeout omitted its bound or diagnostics: $run_output"
else
  pass "missing suites time out with a bounded diagnostic"
fi

if (( failures > 0 )); then
  echo "$failures assertion(s) failed" >&2
  exit 1
fi
echo "All exact-SHA required-check assertions passed."
