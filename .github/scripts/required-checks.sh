#!/usr/bin/env bash
# Fail-closed exact-SHA check gate for the TestFlight workflow.
set -Eeuo pipefail

readonly REQUIRED_CHECKS_PENDING=10
readonly REQUIRED_CHECKS_FAILED=20
readonly REQUIRED_CHECKS_MISSING=21
readonly REQUIRED_CHECKS_INVALID=22
readonly REQUIRED_CHECKS_TIMEOUT_SECONDS="${REQUIRED_CHECKS_TIMEOUT_SECONDS:-1800}"
readonly REQUIRED_CHECKS_POLL_INTERVAL_SECONDS="${REQUIRED_CHECKS_POLL_INTERVAL_SECONDS:-15}"
readonly REQUIRED_CHECKS_MAX_PAGES="${REQUIRED_CHECKS_MAX_PAGES:-10}"
readonly -a REQUIRED_CHECK_CONTRACTS=(
  '.github/workflows/ios.yml|build-and-test'
  '.github/workflows/server.yml|test-and-typecheck'
  '.github/workflows/secret-scan.yml|gitleaks'
)

required_checks_validate_sha() {
  local sha="$1"
  if [[ ! "$sha" =~ ^[0-9a-f]{40}$ ]]; then
    echo "::error::The release gate requires one full lowercase Git SHA; received: $sha" >&2
    return 2
  fi
}

required_checks_validate_configuration() {
  if [[ ! "$REQUIRED_CHECKS_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]]; then
    echo "::error::REQUIRED_CHECKS_TIMEOUT_SECONDS must be a non-negative integer." >&2
    return 2
  fi
  if [[ ! "$REQUIRED_CHECKS_POLL_INTERVAL_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
    echo "::error::REQUIRED_CHECKS_POLL_INTERVAL_SECONDS must be a positive integer." >&2
    return 2
  fi
  if [[ ! "$REQUIRED_CHECKS_MAX_PAGES" =~ ^[1-9][0-9]*$ ]]; then
    echo "::error::REQUIRED_CHECKS_MAX_PAGES must be a positive integer." >&2
    return 2
  fi
}

required_checks_api_collection() {
  local path_and_query="$1"
  local collection_key="$2"
  local output="$3"
  local api_base="${GITHUB_API_URL:-https://api.github.com}"
  local repository="${GITHUB_REPOSITORY:-}"
  local token="${GITHUB_TOKEN:-}"
  local separator='?'
  local page=1
  local total_count=-1
  local fetched_count=0
  local page_count=0
  local page_file=""
  local -a page_files=()

  if [[ -z "$repository" || "$repository" != */* ]]; then
    echo "::error::GITHUB_REPOSITORY must identify the owner and repository." >&2
    return 1
  fi
  if [[ -z "$token" ]]; then
    echo "::error::GITHUB_TOKEN is required to read workflow and check metadata." >&2
    return 1
  fi
  if [[ "$path_and_query" == *\?* ]]; then
    separator='&'
  fi

  while (( page <= REQUIRED_CHECKS_MAX_PAGES )); do
    page_file="${output}.page-${page}"
    page_files+=("$page_file")
    if ! curl \
      --fail-with-body \
      --location \
      --silent \
      --show-error \
      --retry 3 \
      --retry-all-errors \
      --connect-timeout 10 \
      --max-time 30 \
      -H 'Accept: application/vnd.github+json' \
      -H "Authorization: Bearer $token" \
      -H 'X-GitHub-Api-Version: 2022-11-28' \
      -o "$page_file" \
      "${api_base%/}/repos/${repository}/${path_and_query}${separator}per_page=100&page=${page}"
    then
      echo "::error::Could not read GitHub metadata from $path_and_query." >&2
      rm -f "${page_files[@]}"
      return 1
    fi
    if ! jq -e --arg key "$collection_key" '
      (.total_count | type == "number") and
      (.total_count >= 0) and
      (.[$key] | type == "array")
    ' "$page_file" >/dev/null; then
      echo "::error::GitHub returned invalid '$collection_key' metadata from $path_and_query." >&2
      rm -f "${page_files[@]}"
      return 1
    fi

    if (( total_count < 0 )); then
      total_count="$(jq -r '.total_count' "$page_file")"
    fi
    page_count="$(jq -r --arg key "$collection_key" '.[$key] | length' "$page_file")"
    fetched_count=$((fetched_count + page_count))
    if (( fetched_count >= total_count )); then
      break
    fi
    if (( page_count == 0 )); then
      echo "::error::GitHub stopped paginating '$collection_key' before the advertised total." >&2
      rm -f "${page_files[@]}"
      return 1
    fi
    page=$((page + 1))
  done

  if (( fetched_count < total_count )); then
    echo "::error::GitHub '$collection_key' listing exceeded ${REQUIRED_CHECKS_MAX_PAGES} pages; refusing a partial result." >&2
    rm -f "${page_files[@]}"
    return 1
  fi

  jq -s --arg key "$collection_key" '{
    total_count: (map(.total_count) | max),
    items: [.[] | .[$key][]]
  }' "${page_files[@]}" > "$output"
  rm -f "${page_files[@]}"
}

required_checks_select_workflow_run() {
  local sha="$1"
  local workflow_path="$2"
  local runs_file="$3"
  local output="$4"
  local candidates=""
  local candidate_count=0
  local latest_run_number=0
  local latest_count=0

  if ! candidates="$(jq -c \
    --arg path "$workflow_path" \
    --arg sha "$sha" \
    '[
      .items[]
      | select(
          .path == $path and
          .event == "push" and
          .head_branch == "main" and
          .head_sha == $sha
        )
    ]' "$runs_file" 2>/dev/null)"
  then
    echo "::error::Cannot select the push-to-main run for $workflow_path at $sha." >&2
    return 1
  fi
  candidate_count="$(jq -r 'length' <<< "$candidates")"
  if (( candidate_count == 0 )); then
    printf 'null\n' > "$output"
    return 0
  fi
  if ! jq -e 'all(.[];
    (.id | type == "number") and
    (.run_number | type == "number") and
    (.run_attempt | type == "number") and
    (.check_suite_id | type == "number") and
    (.status | type == "string")
  )' <<< "$candidates" >/dev/null; then
    echo "::error::GitHub returned incomplete run provenance for $workflow_path at $sha." >&2
    return 1
  fi

  latest_run_number="$(jq -r 'map(.run_number) | max' <<< "$candidates")"
  latest_count="$(jq -r --argjson run_number "$latest_run_number" '
    map(select(.run_number == $run_number)) | length
  ' <<< "$candidates")"
  if (( latest_count != 1 )); then
    echo "::error::GitHub returned an ambiguous newest push run for $workflow_path at $sha." >&2
    return 1
  fi
  jq --argjson run_number "$latest_run_number" '
    map(select(.run_number == $run_number))[0]
  ' <<< "$candidates" > "$output"
}

required_checks_fetch_snapshot() {
  local sha="$1"
  local output="$2"
  local temporary_directory=""
  local snapshot=""
  local next_snapshot=""
  local contract=""
  local workflow_path=""
  local workflow_id=""
  local check_name=""
  local runs_file=""
  local run_file=""
  local check_runs_file=""
  local check_suite_id=""

  temporary_directory="$(mktemp -d)"
  snapshot="$temporary_directory/snapshot.json"
  next_snapshot="$temporary_directory/snapshot-next.json"
  jq -n --arg sha "$sha" '{source_sha: $sha, contracts: []}' > "$snapshot"

  for contract in "${REQUIRED_CHECK_CONTRACTS[@]}"; do
    workflow_path="${contract%%|*}"
    workflow_id="${workflow_path##*/}"
    check_name="${contract#*|}"
    runs_file="$temporary_directory/${workflow_id}.runs.json"
    run_file="$temporary_directory/${workflow_id}.run.json"
    check_runs_file="$temporary_directory/${workflow_id}.checks.json"

    if ! required_checks_api_collection \
      "actions/workflows/${workflow_id}/runs?branch=main&event=push&exclude_pull_requests=true&head_sha=${sha}" \
      workflow_runs \
      "$runs_file"
    then
      rm -rf "$temporary_directory"
      return 1
    fi
    if ! required_checks_select_workflow_run \
      "$sha" \
      "$workflow_path" \
      "$runs_file" \
      "$run_file"
    then
      rm -rf "$temporary_directory"
      return 1
    fi

    check_suite_id="$(jq -r '.check_suite_id // empty' "$run_file")"
    if [[ -n "$check_suite_id" ]]; then
      if ! required_checks_api_collection \
        "check-suites/${check_suite_id}/check-runs?filter=latest" \
        check_runs \
        "$check_runs_file"
      then
        rm -rf "$temporary_directory"
        return 1
      fi
    else
      jq -n '{total_count: 0, items: []}' > "$check_runs_file"
    fi

    jq \
      --arg workflow_path "$workflow_path" \
      --arg check_name "$check_name" \
      --slurpfile workflow_run "$run_file" \
      --slurpfile check_runs "$check_runs_file" \
      '.contracts += [{
        workflow_path: $workflow_path,
        check_name: $check_name,
        workflow_run: $workflow_run[0],
        check_runs: $check_runs[0].items
      }]' \
      "$snapshot" > "$next_snapshot"
    mv "$next_snapshot" "$snapshot"
  done

  cp "$snapshot" "$output"
  rm -rf "$temporary_directory"
}

required_checks_evaluate_snapshot() {
  local sha="$1"
  local snapshot="$2"
  local contract=""
  local workflow_path=""
  local check_name=""
  local contract_json=""
  local contract_count=0
  local workflow_run=""
  local workflow_status=""
  local workflow_conclusion=""
  local workflow_run_id=""
  local workflow_attempt=""
  local check_suite_id=""
  local checks=""
  local matches=""
  local match_count=0
  local check_run=""
  local check_status=""
  local check_conclusion=""
  local check_run_id=""
  local details_url=""
  local observed_checks=""
  local started_at=""
  local completed_at=""
  local successes=0
  local pending=0
  local failed=0
  local missing=0

  required_checks_validate_sha "$sha" || return "$REQUIRED_CHECKS_INVALID"
  if ! jq -e --arg sha "$sha" '
    .source_sha == $sha and
    (.contracts | type == "array")
  ' "$snapshot" >/dev/null 2>&1; then
    echo "::error::Cannot evaluate malformed gate metadata for exact SHA $sha." >&2
    return "$REQUIRED_CHECKS_INVALID"
  fi

  for contract in "${REQUIRED_CHECK_CONTRACTS[@]}"; do
    workflow_path="${contract%%|*}"
    check_name="${contract#*|}"
    contract_json="$(jq -c \
      --arg workflow_path "$workflow_path" \
      --arg check_name "$check_name" \
      '[
        .contracts[]
        | select(
            .workflow_path == $workflow_path and
            .check_name == $check_name
          )
      ]' "$snapshot")"
    contract_count="$(jq -r 'length' <<< "$contract_json")"
    if (( contract_count != 1 )); then
      echo "::error::Gate metadata contains $contract_count contracts for $workflow_path -> $check_name; expected exactly one." >&2
      failed=$((failed + 1))
      continue
    fi
    contract_json="$(jq -c '.[0]' <<< "$contract_json")"
    workflow_run="$(jq -c '.workflow_run' <<< "$contract_json")"
    if [[ "$workflow_run" == "null" ]]; then
      echo "::notice::No push-to-main workflow suite for $workflow_path has appeared at exact SHA $sha."
      missing=$((missing + 1))
      continue
    fi
    if ! jq -e \
      --arg workflow_path "$workflow_path" \
      --arg sha "$sha" '
      .path == $workflow_path and
      .event == "push" and
      .head_branch == "main" and
      .head_sha == $sha and
      (.id | type == "number") and
      (.run_attempt | type == "number") and
      (.check_suite_id | type == "number") and
      (.status | type == "string")
    ' <<< "$workflow_run" >/dev/null; then
      echo "::error::Workflow provenance does not match $workflow_path on main at exact SHA $sha." >&2
      failed=$((failed + 1))
      continue
    fi

    workflow_status="$(jq -r '.status' <<< "$workflow_run")"
    workflow_conclusion="$(jq -r '.conclusion // "null"' <<< "$workflow_run")"
    workflow_run_id="$(jq -r '.id' <<< "$workflow_run")"
    workflow_attempt="$(jq -r '.run_attempt' <<< "$workflow_run")"
    check_suite_id="$(jq -r '.check_suite_id' <<< "$workflow_run")"
    echo "Workflow $workflow_path: run=$workflow_run_id attempt=$workflow_attempt suite=$check_suite_id status=$workflow_status conclusion=$workflow_conclusion exact_sha=$sha."

    if ! checks="$(jq -c '.check_runs | if type == "array" then . else error("not an array") end' <<< "$contract_json" 2>/dev/null)"; then
      echo "::error::Gate metadata has invalid check runs for $workflow_path at $sha." >&2
      failed=$((failed + 1))
      continue
    fi
    if ! matches="$(jq -c \
      --arg name "$check_name" \
      --arg sha "$sha" \
      --argjson suite_id "$check_suite_id" '
      [
        .[]
        | select(
            .name == $name and
            .head_sha == $sha and
            .app.slug == "github-actions" and
            .check_suite.id == $suite_id
          )
      ]' <<< "$checks" 2>/dev/null)"
    then
      echo "::error::Cannot evaluate check '$check_name' in workflow suite $check_suite_id." >&2
      failed=$((failed + 1))
      continue
    fi
    match_count="$(jq -r 'length' <<< "$matches")"
    if (( match_count == 0 )); then
      observed_checks="$(jq -r '
        if length == 0 then
          "none"
        else
          map(
            "name=" + (.name // "<unnamed>") +
            " sha=" + (.head_sha // "<missing>") +
            " suite=" + ((.check_suite.id // "<missing>") | tostring) +
            " app=" + (.app.slug // "<missing>") +
            " status=" + (.status // "<missing>") +
            " conclusion=" + (.conclusion // "null")
          )
          | unique
          | join("; ")
        end
      ' <<< "$checks")"
      case "$workflow_status" in
        queued|in_progress|requested|waiting|pending)
          echo "::notice::Exact check '$check_name' has not appeared in pending suite $check_suite_id (visible: $observed_checks)."
          pending=$((pending + 1))
          ;;
        completed)
          echo "::error::Completed suite $check_suite_id is missing exact check '$check_name' for SHA $sha (visible: $observed_checks)." >&2
          failed=$((failed + 1))
          ;;
        *)
          echo "::error::Workflow $workflow_path has unexpected status '$workflow_status' while '$check_name' is missing." >&2
          failed=$((failed + 1))
          ;;
      esac
      continue
    fi
    if (( match_count > 1 )); then
      echo "::error::Suite $check_suite_id returned $match_count latest exact-name checks '$check_name' for SHA $sha; refusing ambiguity." >&2
      failed=$((failed + 1))
      continue
    fi

    check_run="$(jq -c '.[0]' <<< "$matches")"
    check_status="$(jq -r '.status // "null"' <<< "$check_run")"
    check_conclusion="$(jq -r '.conclusion // "null"' <<< "$check_run")"
    check_run_id="$(jq -r '.id // "unknown"' <<< "$check_run")"
    details_url="$(jq -r '.details_url // "no details URL"' <<< "$check_run")"
    started_at="$(jq -r '.started_at // "unknown"' <<< "$check_run")"
    completed_at="$(jq -r '.completed_at // "unknown"' <<< "$check_run")"
    echo "Check $check_name: run=$check_run_id suite=$check_suite_id status=$check_status conclusion=$check_conclusion exact_sha=$sha app=github-actions started=$started_at completed=$completed_at details=$details_url."

    # A rerun changes the workflow run to a nonterminal state before its new
    # check run is guaranteed to replace the previous attempt's success.
    # Never accept that stale window; wait for the selected suite to finish.
    case "$workflow_status" in
      completed)
        ;;
      queued|in_progress|requested|waiting|pending)
        echo "::notice::Workflow $workflow_path is still $workflow_status; its visible '$check_name' result cannot pass until the suite completes."
        pending=$((pending + 1))
        continue
        ;;
      *)
        echo "::error::Workflow $workflow_path has unexpected status '$workflow_status'." >&2
        failed=$((failed + 1))
        continue
        ;;
    esac

    if [[ "$check_status" == "completed" && "$check_conclusion" == "success" ]]; then
      successes=$((successes + 1))
      continue
    fi
    case "$check_status" in
      queued|in_progress|requested|waiting|pending)
        pending=$((pending + 1))
        ;;
      *)
        echo "::error::Check '$check_name' cannot satisfy exact SHA $sha: status=$check_status conclusion=$check_conclusion. Only completed/success is accepted." >&2
        failed=$((failed + 1))
        ;;
    esac
  done

  if (( failed > 0 )); then
    return "$REQUIRED_CHECKS_FAILED"
  fi
  if (( missing > 0 )); then
    return "$REQUIRED_CHECKS_MISSING"
  fi
  if (( pending > 0 )); then
    return "$REQUIRED_CHECKS_PENDING"
  fi
  if (( successes != ${#REQUIRED_CHECK_CONTRACTS[@]} )); then
    echo "::error::Exact-SHA gate reached an inconsistent state for $sha." >&2
    return "$REQUIRED_CHECKS_INVALID"
  fi
}

required_checks_wait() {
  local sha="$1"
  local temporary_directory=""
  local snapshot=""
  local state=0
  local started_at="$SECONDS"
  local elapsed=0
  local remaining=0
  local sleep_for=0

  temporary_directory="$(mktemp -d)"
  snapshot="$temporary_directory/check-snapshot.json"

  while true; do
    if ! required_checks_fetch_snapshot "$sha" "$snapshot"; then
      rm -rf "$temporary_directory"
      return 1
    fi

    set +e
    required_checks_evaluate_snapshot "$sha" "$snapshot"
    state=$?
    set -e
    case "$state" in
      0)
        echo "All exact-name push-to-main checks succeeded for immutable SHA $sha."
        rm -rf "$temporary_directory"
        return 0
        ;;
      "$REQUIRED_CHECKS_PENDING"|"$REQUIRED_CHECKS_MISSING")
        elapsed=$((SECONDS - started_at))
        if (( elapsed >= REQUIRED_CHECKS_TIMEOUT_SECONDS )); then
          echo "::error::Timed out after ${REQUIRED_CHECKS_TIMEOUT_SECONDS}s waiting for push-to-main checks on exact SHA $sha. Missing or nonterminal suites/checks never satisfy the release gate." >&2
          rm -rf "$temporary_directory"
          return 1
        fi
        remaining=$((REQUIRED_CHECKS_TIMEOUT_SECONDS - elapsed))
        sleep_for="$REQUIRED_CHECKS_POLL_INTERVAL_SECONDS"
        if (( sleep_for > remaining )); then
          sleep_for="$remaining"
        fi
        echo "Waiting ${sleep_for}s before polling exact SHA $sha again (${elapsed}s elapsed; ${remaining}s remain)."
        sleep "$sleep_for"
        ;;
      "$REQUIRED_CHECKS_FAILED"|"$REQUIRED_CHECKS_INVALID")
        rm -rf "$temporary_directory"
        return 1
        ;;
      *)
        echo "::error::Exact-SHA gate returned unexpected state $state for $sha." >&2
        rm -rf "$temporary_directory"
        return 1
        ;;
    esac
  done
}

required_checks_main() {
  if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <full-source-sha>" >&2
    return 2
  fi
  required_checks_validate_configuration
  required_checks_validate_sha "$1"
  required_checks_wait "$1"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  required_checks_main "$@"
fi
