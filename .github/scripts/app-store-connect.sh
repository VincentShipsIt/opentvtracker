# Shared App Store Connect request helpers for the TestFlight workflow.
# Source this file after exporting ASC_TOKEN. Tests inject ASC_CURL.

ASC_CONNECT_TIMEOUT="${ASC_CONNECT_TIMEOUT:-15}"
ASC_MAX_TIME="${ASC_MAX_TIME:-45}"
ASC_GET_RETRIES="${ASC_GET_RETRIES:-3}"
ASC_MAX_PAGES="${ASC_MAX_PAGES:-20}"
ASC_TMPDIR="${ASC_TMPDIR:-${RUNNER_TEMP:-/tmp}}"
ASC_LAST_STATUS=""

asc_curl() {
  local method="$1"
  local url="$2"
  local output="$3"
  shift 3
  "${ASC_CURL:-curl}" --globoff -sS \
    --connect-timeout "$ASC_CONNECT_TIMEOUT" \
    --max-time "$ASC_MAX_TIME" \
    -o "$output" \
    -w '%{http_code}' \
    -H "Authorization: Bearer ${ASC_TOKEN:-}" \
    -X "$method" \
    "$@" \
    "$url"
}

asc_should_retry_status() {
  local status="$1"
  [[ "$status" == "408" || "$status" == "429" || "$status" =~ ^5[0-9][0-9]$ ]]
}

asc_get() {
  local url="$1"
  local output="$2"
  local attempt=1
  local status=""
  ASC_LAST_STATUS=""

  while (( attempt <= ASC_GET_RETRIES )); do
    if status="$(asc_curl GET "$url" "$output")"; then
      ASC_LAST_STATUS="$status"
      if [[ "$status" == "200" ]]; then
        return 0
      fi
      if (( attempt < ASC_GET_RETRIES )) && asc_should_retry_status "$status"; then
        sleep "$attempt"
        attempt=$((attempt + 1))
        continue
      fi
      cat "$output" >&2 || true
      echo "::error::App Store Connect GET failed with HTTP $status: $url" >&2
      return 1
    fi
    ASC_LAST_STATUS="000"
    if (( attempt >= ASC_GET_RETRIES )); then
      echo "::error::App Store Connect GET exhausted ${ASC_GET_RETRIES} attempts for $url" >&2
      return 1
    fi
    sleep "$attempt"
    attempt=$((attempt + 1))
  done
  return 1
}

asc_post() {
  local url="$1"
  local request="$2"
  local output="$3"
  local status=""
  ASC_LAST_STATUS=""

  if ! status="$(asc_curl POST "$url" "$output" \
    -H 'Content-Type: application/json' \
    --data-binary "@$request")"; then
    ASC_LAST_STATUS="000"
    echo "::error::App Store Connect POST failed to connect: $url" >&2
    return 1
  fi
  ASC_LAST_STATUS="$status"
  if [[ "$status" != "201" ]]; then
    cat "$output" >&2 || true
    echo "::error::App Store Connect POST failed with HTTP $status: $url" >&2
    return 1
  fi
}

asc_normalize_next_url() {
  local next="$1"
  if [[ -z "$next" ]]; then
    return 0
  fi
  if [[ "$next" == https://* ]]; then
    printf '%s' "$next"
    return 0
  fi
  printf 'https://api.appstoreconnect.apple.com%s' "$next"
}

asc_get_collection() {
  local url="$1"
  local output="$2"
  local page=0
  local pages=()
  local tmp=""
  local next="$url"

  while [[ -n "$next" ]]; do
    page=$((page + 1))
    if (( page > ASC_MAX_PAGES )); then
      echo "::error::App Store Connect listing exceeded ${ASC_MAX_PAGES} pages before finding a last page: $url" >&2
      return 1
    fi
    tmp="$ASC_TMPDIR/asc-page-${page}-$$.json"
    if ! asc_get "$next" "$tmp"; then
      echo "::error::Stopped before treating the listing as complete; a later page was not fetched." >&2
      return 1
    fi
    if jq -e '.links.next != null and .links.next != ""' "$tmp" >/dev/null \
      && [[ -z "$(jq -r '.links.next // empty' "$tmp")" ]]; then
      echo "::error::App Store Connect returned an unusable pagination link for $next" >&2
      return 1
    fi
    pages+=("$tmp")
    next="$(asc_normalize_next_url "$(jq -r '.links.next // empty' "$tmp")")"
  done

  jq -s '{data: map(.data // []) | add}' "${pages[@]}" > "$output"
}
