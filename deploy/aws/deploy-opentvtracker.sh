#!/usr/bin/env bash
set -Eeuo pipefail

readonly artifact_bucket="relaypress-production-deploy-948918267147-us-west-1"
readonly artifact_region="us-west-1"
readonly parameter_region="us-east-1"
readonly parameter_path="/shipshit/production/opentvtracker/"
readonly image_key="${1:-}"
readonly sha="${2:-}"

if [[ ! "$sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Expected a full lowercase Git SHA as the second argument" >&2
  exit 2
fi
if [[ "$image_key" != "images/api-opentvtracker-dev-${sha}.tar.gz" ]]; then
  echo "Image key does not match the requested Git SHA" >&2
  exit 2
fi

readonly image="api-opentvtracker-dev:${sha}"
readonly container="api-opentvtracker-dev"
readonly candidate="${container}-candidate"
readonly previous="${container}-previous"
readonly network="shipshit"
readonly port="8787"
readonly environment_directory="/etc/opentvtracker"
readonly environment_file="${environment_directory}/production.env"
readonly artifact_directory="/var/lib/opentvtracker"

install -d -m 700 "$environment_directory" "$artifact_directory"
umask 077
temporary_environment="$(mktemp "${environment_directory}/production.env.XXXXXX")"
artifact_file="$(mktemp "${artifact_directory}/api-opentvtracker-dev.XXXXXX.tar.gz")"
trap 'rm -f "$temporary_environment" "$artifact_file"' EXIT

reclaim_docker_space() {
  docker container prune -f || true
  docker builder prune -f || true
  docker image prune -f || true
  docker image prune -af --filter "until=24h" || true
  docker network prune -f || true
}

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to validate SSM parameters safely" >&2
  exit 1
fi

parameter_rows_json="$(
  aws ssm get-parameters-by-path \
    --path "$parameter_path" \
    --recursive \
    --with-decryption \
    --region "$parameter_region" \
    --query "Parameters[].[Name,Value]" \
    --output json
)"
if ! jq -e '
  type == "array" and
  all(.[];
    type == "array" and
    length == 2 and
    (.[0] | type == "string") and
    (.[1] | type == "string")
  )
' <<<"$parameter_rows_json" >/dev/null 2>&1; then
  echo "SSM response must contain string name/value pairs" >&2
  exit 1
fi
if [[ "$(jq -r 'length' <<<"$parameter_rows_json")" == "0" ]]; then
  echo "No SSM parameters found under ${parameter_path}" >&2
  exit 1
fi

declare -A seen_keys=()
declare -A parameter_values=()
parameter_keys=()
while IFS= read -r parameter_row; do
  if jq -e '.[1] | contains("\u0000") or contains("\r") or contains("\n")' \
    <<<"$parameter_row" >/dev/null
  then
    echo "SSM values must not contain NUL, CR, or LF" >&2
    exit 1
  fi
  parameter_name="$(jq -r '.[0]' <<<"$parameter_row")"
  parameter_value="$(jq -r '.[1]' <<<"$parameter_row")"
  if [[ "$parameter_name" != "${parameter_path}"* ]]; then
    echo "SSM parameter is outside the required path" >&2
    exit 1
  fi
  parameter_key="${parameter_name##*/}"
  if [[ ! "$parameter_key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    echo "Invalid environment key from SSM: ${parameter_key}" >&2
    exit 1
  fi
  if [[ -n "${seen_keys[$parameter_key]:-}" ]]; then
    echo "Duplicate SSM parameter leaf: ${parameter_key}" >&2
    exit 1
  fi
  seen_keys["$parameter_key"]=1
  parameter_values["$parameter_key"]="$parameter_value"
  parameter_keys+=("$parameter_key")
done < <(jq -c '.[]' <<<"$parameter_rows_json")

required_keys=(
  DATABASE_URL
  APP_ATTEST_MODE
  APP_ATTEST_TEAM_ID
  APP_ATTEST_BUNDLE_ID
  APP_ATTEST_TOKEN_SECRET
  TMDB_READ_ACCESS_TOKEN
)
for required_key in "${required_keys[@]}"; do
  if [[ -z "${seen_keys[$required_key]:-}" ]]; then
    echo "Required SSM parameter is missing: ${parameter_path}${required_key}" >&2
    exit 1
  fi
done

if [[ "${parameter_values[APP_ATTEST_MODE]}" != "production" ]]; then
  echo "APP_ATTEST_MODE must be exactly production for deployment" >&2
  exit 1
fi
if [[ -n "${seen_keys[APP_ATTEST_DEVELOPMENT_BYPASS_TOKEN]:-}" ]]; then
  echo "APP_ATTEST_DEVELOPMENT_BYPASS_TOKEN is forbidden in production deployment" >&2
  exit 1
fi

for parameter_key in "${parameter_keys[@]}"; do
  printf '%s=%s\n' \
    "$parameter_key" \
    "${parameter_values[$parameter_key]}" \
    >>"$temporary_environment"
done

printf '%s\n' \
  "NODE_ENV=production" \
  "PORT=${port}" \
  "NODE_EXTRA_CA_CERTS=/etc/ssl/certs/aws-rds-global-bundle.pem" \
  >>"$temporary_environment"
install -m 600 "$temporary_environment" "$environment_file"

reclaim_docker_space
docker network inspect "$network" >/dev/null
aws s3 cp \
  "s3://${artifact_bucket}/${image_key}" \
  "$artifact_file" \
  --region "$artifact_region" \
  --only-show-errors

gzip -dc "$artifact_file" | docker load >/dev/null
docker image inspect "$image" >/dev/null

docker rm -f "$candidate" >/dev/null 2>&1 || true
docker run -d \
  --name "$candidate" \
  --network "$network" \
  --env-file "$environment_file" \
  --restart no \
  --memory 256m \
  --memory-swap 384m \
  --cpus 0.5 \
  --pids-limit 192 \
  --security-opt no-new-privileges:true \
  --cap-drop ALL \
  --label "dev.shipshit.service=api-opentvtracker-dev" \
  --log-driver json-file \
  --log-opt max-size=10m \
  --log-opt max-file=3 \
  "$image" >/dev/null

wait_for_health() {
  local target="$1"
  for _ in $(seq 1 36); do
    status="$(
      docker inspect \
        --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
        "$target"
    )"
    if [[ "$status" == "healthy" ]]; then
      return 0
    fi
    if [[ "$status" == "unhealthy" || "$status" == "exited" || "$status" == "dead" ]]; then
      docker logs --tail 160 "$target" >&2 || true
      return 1
    fi
    sleep 5
  done
  docker logs --tail 160 "$target" >&2 || true
  return 1
}

if ! wait_for_health "$candidate"; then
  docker rm -f "$candidate" >/dev/null 2>&1 || true
  exit 1
fi

docker rm -f "$previous" >/dev/null 2>&1 || true
had_previous=false
if docker inspect "$container" >/dev/null 2>&1; then
  had_previous=true
  docker stop "$container" >/dev/null
  docker rename "$container" "$previous"
fi
docker rename "$candidate" "$container"
docker update --restart unless-stopped "$container" >/dev/null

rollback() {
  echo "OpenTV Tracker cutover failed; rolling back" >&2
  docker rm -f "$container" >/dev/null 2>&1 || true
  if [[ "$had_previous" == "true" ]] && docker inspect "$previous" >/dev/null 2>&1; then
    docker rename "$previous" "$container"
    docker start "$container" >/dev/null
  fi
  docker exec shipshit-caddy caddy reload --config /etc/caddy/Caddyfile >/dev/null 2>&1 || true
}

if ! docker exec shipshit-caddy caddy validate --config /etc/caddy/Caddyfile >/dev/null; then
  rollback
  exit 1
fi
if ! docker exec shipshit-caddy caddy reload --config /etc/caddy/Caddyfile >/dev/null; then
  rollback
  exit 1
fi
if ! wait_for_health "$container"; then
  rollback
  exit 1
fi

external_healthy=false
for _ in $(seq 1 30); do
  if curl --fail --silent --show-error --max-time 5 \
    --resolve "api.opentvtracker.dev:443:127.0.0.1" \
    "https://api.opentvtracker.dev/health" >/dev/null 2>&1
  then
    external_healthy=true
    break
  fi
  sleep 2
done
if [[ "$external_healthy" != "true" ]]; then
  rollback
  exit 1
fi

docker rm -f "$previous" >/dev/null 2>&1 || true
docker image prune -f >/dev/null 2>&1 || true

echo "OpenTV Tracker API deployed: ${image}"
