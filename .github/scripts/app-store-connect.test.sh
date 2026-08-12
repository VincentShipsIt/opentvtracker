#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=app-store-connect.sh
source "$ROOT/.github/scripts/app-store-connect.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ASC_TMPDIR="$TMP"
ASC_TOKEN="test-token"
ASC_GET_RETRIES=3
ASC_CONNECT_TIMEOUT=1
ASC_MAX_TIME=2
ASC_MAX_PAGES=5
failures=0

fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

pass() {
  echo "PASS: $*"
}

write_mock() {
  cat > "$TMP/mock-curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=""
method="GET"
url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|-X|--data-binary|--connect-timeout|--max-time|-H|-w)
      if [[ "$1" == "-o" ]]; then output="$2"; fi
      if [[ "$1" == "-X" ]]; then method="$2"; fi
      shift 2
      ;;
    --globoff|-sS)
      shift
      ;;
    https://*|http://*)
      url="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

log="${MOCK_LOG:-/dev/null}"
printf '%s %s\n' "$method" "$url" >> "$log"

if [[ -n "${MOCK_SLEEP:-}" ]]; then
  sleep "$MOCK_SLEEP"
fi

if [[ "${MOCK_EXIT:-0}" != "0" ]]; then
  exit "$MOCK_EXIT"
fi

case "$url" in
  */page-one)
    printf '%s' '{"data":[{"id":"first","attributes":{"identifier":"first.app"}}],"links":{"next":"https://api.appstoreconnect.apple.com/v1/bundleIds?cursor=2"}}' > "$output"
    printf '200'
    ;;
  */bundleIds\?cursor=2|*/cursor=2)
    printf '%s' '{"data":[{"id":"second","attributes":{"identifier":"dev.opentvtracker.app"}}],"links":{}}' > "$output"
    printf '200'
    ;;
  */relative-next)
    printf '%s' '{"data":[{"id":"first"}],"links":{"next":"/v1/bundleIds?cursor=2"}}' > "$output"
    printf '200'
    ;;
  */broken-next)
    printf '%s' '{"data":[{"id":"first"}],"links":{"next":"https://api.appstoreconnect.apple.com/v1/missing-page"}}' > "$output"
    printf '200'
    ;;
  */missing-page)
    printf '%s' '{"errors":[{"status":"500"}]}' > "$output"
    printf '500'
    ;;
  */retry-then-ok)
    count_file="${MOCK_COUNT_FILE:?}"
    count="$(cat "$count_file")"
    count=$((count + 1))
    printf '%s' "$count" > "$count_file"
    if (( count < 3 )); then
      printf '%s' '{"errors":[{"status":"503"}]}' > "$output"
      printf '503'
    else
      printf '%s' '{"data":[{"id":"ok"}],"links":{}}' > "$output"
      printf '200'
    fi
    ;;
  */transport)
    exit 28
    ;;
  */create-profile)
    printf '%s' '{"data":{"id":"profile","attributes":{"name":"created"}}}' > "$output"
    printf '201'
    ;;
  */create-profile-fail)
    printf '%s' '{"errors":[{"status":"409"}]}' > "$output"
    printf '409'
    ;;
  *)
    printf '%s' '{"errors":[{"status":"404"}]}' > "$output"
    printf '404'
    ;;
esac
EOF
  chmod +x "$TMP/mock-curl"
  ASC_CURL="$TMP/mock-curl"
  MOCK_LOG="$TMP/curl.log"
  : > "$MOCK_LOG"
  export MOCK_LOG
}

write_mock

if ! asc_get_collection "https://api.appstoreconnect.apple.com/v1/page-one" "$TMP/all.json"; then
  fail "paginated collection should succeed"
else
  ids="$(jq -r '.data[].attributes.identifier // .data[].id' "$TMP/all.json" | tr '\n' ' ')"
  if [[ "$ids" == *"first.app"*"dev.opentvtracker.app"* ]]; then
    pass "follows links.next and merges pages"
  else
    fail "merged pages missing expected identifiers: $ids"
  fi
fi

if jq -e --arg identifier "dev.opentvtracker.app" \
  '.data[] | select(.attributes.identifier == $identifier)' \
  "$TMP/all.json" >/dev/null; then
  pass "target on page two is visible after pagination"
else
  fail "page-two identifier was treated as missing"
fi

write_mock
if ! asc_get_collection "https://api.appstoreconnect.apple.com/v1/relative-next" "$TMP/relative.json"; then
  fail "relative pagination link should be resolved"
else
  pass "resolves relative links.next"
fi

write_mock
if asc_get_collection "https://api.appstoreconnect.apple.com/v1/broken-next" "$TMP/broken.json"; then
  fail "failed continuation must not report a complete listing"
else
  pass "fails closed when a later page cannot be fetched"
fi

write_mock
MOCK_COUNT_FILE="$TMP/retry-count"
printf '0' > "$MOCK_COUNT_FILE"
export MOCK_COUNT_FILE
if ! asc_get "https://api.appstoreconnect.apple.com/v1/retry-then-ok" "$TMP/retry.json"; then
  fail "GET should retry 503 then succeed"
else
  attempts="$(cat "$MOCK_COUNT_FILE")"
  if [[ "$attempts" == "3" ]]; then
    pass "GET retried transient 503 responses"
  else
    fail "expected 3 GET attempts, got $attempts"
  fi
fi
unset MOCK_COUNT_FILE

write_mock
ASC_GET_RETRIES=2
if asc_get "https://api.appstoreconnect.apple.com/v1/transport" "$TMP/transport.json"; then
  fail "transport failures should exhaust retries"
else
  [[ "$ASC_LAST_STATUS" == "000" ]] && pass "transport failure is not treated as HTTP success" \
    || fail "expected status 000 after curl exit"
fi
ASC_GET_RETRIES=3

write_mock
printf '{}' > "$TMP/request.json"
if ! asc_post "https://api.appstoreconnect.apple.com/v1/create-profile" "$TMP/request.json" "$TMP/created.json"; then
  fail "POST 201 should succeed"
else
  pass "POST accepts 201"
fi

write_mock
if asc_post "https://api.appstoreconnect.apple.com/v1/create-profile-fail" "$TMP/request.json" "$TMP/created-fail.json"; then
  fail "POST 409 should fail without retry"
else
  attempts="$(grep -c 'POST ' "$MOCK_LOG" || true)"
  if [[ "$attempts" == "1" ]]; then
    pass "POST is not retried"
  else
    fail "POST was attempted $attempts times"
  fi
fi

if (( failures > 0 )); then
  echo "$failures assertion(s) failed" >&2
  exit 1
fi
echo "All App Store Connect helper assertions passed."
