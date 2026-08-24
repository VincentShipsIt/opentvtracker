#!/usr/bin/env bash
# Cross-check objective repository documentation facts against their owners.
# Markdown link literals intentionally keep backticks inert.
# shellcheck disable=SC2016
set -Eeuo pipefail

ROOT="${OPENTV_REPOSITORY_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
readonly ROOT
readonly PROJECT_SPEC="$ROOT/project.yml"
readonly PACKAGE_LOCK="$ROOT/OpenTVTracker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
readonly REQUIRED_CHECKS_SCRIPT="$ROOT/.github/scripts/required-checks.sh"
readonly README="$ROOT/README.md"
readonly ROADMAP="$ROOT/docs/ROADMAP.md"
readonly THIRD_PARTY="$ROOT/docs/THIRD_PARTY_LICENSES.md"
readonly PUBLIC_RELEASE_CHECKLIST="$ROOT/docs/PUBLIC_RELEASE_CHECKLIST.md"
readonly TESTFLIGHT_RELEASES="$ROOT/docs/TESTFLIGHT_RELEASES.md"
readonly SWIFTLINT_CONFIG="$ROOT/.swiftlint.yml"

fact_error() {
  local fact="$1"
  local file="$2"
  shift 2
  local relative="${file#"$ROOT/"}"
  printf '::error file=%s,title=Repository fact (%s)::%s\n' \
    "$relative" "$fact" "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 \
    || fact_error "tooling" "$PROJECT_SPEC" "Required command is unavailable: $1"
}

require_file() {
  local fact="$1"
  local file="$2"
  [[ -f "$file" ]] || fact_error "$fact" "$file" "Required owner or documentation file is missing."
}

yaml_scalar() {
  local key="$1"
  local fact="$2"
  local matches=""
  local count=0

  matches="$(sed -nE \
    "s/^[[:space:]]*${key}:[[:space:]]*([^#[:space:]]+).*$/\\1/p" \
    "$PROJECT_SPEC")"
  count="$(awk 'NF { count += 1 } END { print count + 0 }' <<< "$matches")"
  [[ "$count" == "1" ]] \
    || fact_error "$fact" "$PROJECT_SPEC" \
      "Expected exactly one $key owner in project.yml; found $count."
  printf '%s' "$matches"
}

zipfoundation_exact_version() {
  local parsed=""
  local block_count=0
  local count=0
  local value=""

  parsed="$(awk '
    /^packages:[[:space:]]*(#.*)?$/ { in_packages = 1; next }
    in_packages && /^[^[:space:]#]/ { in_packages = 0; in_zipfoundation = 0 }
    in_packages && /^  ZIPFoundation:[[:space:]]*(#.*)?$/ {
      block_count += 1
      in_zipfoundation = 1
      next
    }
    in_packages && /^  [A-Za-z0-9_.-]+:[[:space:]]*(#.*)?$/ {
      in_zipfoundation = 0
    }
    in_zipfoundation && /^    exactVersion:[[:space:]]*[^#[:space:]]+/ {
      candidate = $0
      sub(/^    exactVersion:[[:space:]]*/, "", candidate)
      sub(/[[:space:]#].*$/, "", candidate)
      version_count += 1
      if (version_count == 1) {
        version = candidate
      }
    }
    END { printf "%d|%d|%s\n", block_count + 0, version_count + 0, version }
  ' "$PROJECT_SPEC")"
  IFS='|' read -r block_count count value <<< "$parsed"
  [[ "$block_count" == "1" ]] \
    || fact_error "ZIPFoundation exact version" "$PROJECT_SPEC" \
      "Expected exactly one packages.ZIPFoundation mapping in project.yml; found $block_count."
  [[ "$count" == "1" ]] \
    || fact_error "ZIPFoundation exact version" "$PROJECT_SPEC" \
      "Expected exactly one exactVersion inside packages.ZIPFoundation; found $count."
  printf '%s' "$value"
}

require_literal() {
  local fact="$1"
  local file="$2"
  local literal="$3"
  grep -Fq -- "$literal" "$file" \
    || fact_error "$fact" "$file" "Expected the owner reference '$literal'."
}

reject_literal() {
  local fact="$1"
  local file="$2"
  local literal="$3"
  if grep -Fq -- "$literal" "$file"; then
    fact_error "$fact" "$file" "Stale or duplicated fact '$literal' must be replaced with its owner reference."
  fi
}

reject_version_claims() {
  local file="$1"
  if grep -Eiq 'marketing[[:space:]]+version[^[:cntrl:][:digit:]]{0,40}[0-9]+\.[0-9]+\.[0-9]+' "$file"; then
    fact_error "marketing version" "$file" \
      "Do not duplicate the marketing version; link to project.yml."
  fi
  if grep -Eiq 'build[[:space:]]+number[^[:cntrl:][:digit:]]{0,40}[0-9]+' "$file"; then
    fact_error "build number" "$file" \
      "Do not duplicate the build number; link to project.yml."
  fi
}

reject_dependency_claims() {
  local file="$1"
  if grep -Eiq 'ZIPFoundation[^[:cntrl:]]{0,80}[0-9]+\.[0-9]+\.[0-9]+' "$file"; then
    fact_error "ZIPFoundation exact version" "$file" \
      "Do not duplicate a ZIPFoundation version; link to project.yml."
  fi
  if grep -Eiq 'package[[:space:]]+revision[^[:cntrl:]]{0,40}[0-9a-f]{40}' "$file" \
    || grep -Eiq 'ZIPFoundation[^[:cntrl:]]{0,80}(revision|commit|resolved[[:space:]]+to)[^[:cntrl:][:xdigit:]]{0,20}[0-9a-f]{40}' "$file"
  then
    fact_error "ZIPFoundation resolved revision" "$file" \
      "Do not duplicate a package revision; link to Package.resolved."
  fi
}

workflow_job_block() {
  local workflow="$1"
  local check_name="$2"
  awk -v job="$check_name" '
    $0 == "  " job ":" { found = 1; print; next }
    found && $0 ~ /^  [A-Za-z0-9_-]+:([[:space:]]*#.*)?$/ { exit }
    found { print }
  ' "$workflow"
}

validate_release_contract() {
  local contract=""
  local workflow_path=""
  local check_name=""
  local workflow=""
  local job_count=0
  local job_block=""
  local explicit_names=""
  local explicit_name_count=0
  local seen='|'

  # The helper is the machine-readable owner of this array. Sourcing it avoids
  # copying workflow/check values into another file.
  # shellcheck disable=SC1090
  source "$REQUIRED_CHECKS_SCRIPT"
  (( ${#REQUIRED_CHECK_CONTRACTS[@]} > 0 )) \
    || fact_error "release gate" "$REQUIRED_CHECKS_SCRIPT" \
      "The required workflow/check contract must not be empty."

  for contract in "${REQUIRED_CHECK_CONTRACTS[@]}"; do
    [[ "$contract" == *'|'* && "$contract" != '|'* && "$contract" != *'|' ]] \
      || fact_error "release gate" "$REQUIRED_CHECKS_SCRIPT" \
        "Malformed workflow/check contract: $contract"
    if [[ "$seen" == *"|$contract|"* ]]; then
      fact_error "release gate" "$REQUIRED_CHECKS_SCRIPT" \
        "Duplicate workflow/check contract: $contract"
    fi
    seen+="$contract|"

    workflow_path="${contract%%|*}"
    check_name="${contract#*|}"
    [[ "$workflow_path" =~ ^\.github/workflows/[A-Za-z0-9_-]+\.yml$ ]] \
      || fact_error "release gate" "$REQUIRED_CHECKS_SCRIPT" \
        "Workflow path must be a tracked .github/workflows/*.yml file: $workflow_path"
    [[ "$check_name" =~ ^[A-Za-z0-9_-]+$ ]] \
      || fact_error "release gate" "$REQUIRED_CHECKS_SCRIPT" \
        "Check name must be a stable workflow job identifier: $check_name"

    workflow="$ROOT/$workflow_path"
    require_file "release gate" "$workflow"
    job_count="$(grep -Ec "^  ${check_name}:([[:space:]]*#.*)?$" "$workflow" || true)"
    [[ "$job_count" == "1" ]] \
      || fact_error "release gate" "$workflow" \
        "Contract '$contract' requires exactly one job id '$check_name'; found $job_count."

    job_block="$(workflow_job_block "$workflow" "$check_name")"
    explicit_names="$(sed -nE 's/^    name:[[:space:]]*(.*)[[:space:]]*$/\1/p' <<< "$job_block")"
    explicit_name_count="$(awk 'NF { count += 1 } END { print count + 0 }' <<< "$explicit_names")"
    if (( explicit_name_count > 1 )); then
      fact_error "release gate" "$workflow" \
        "Job '$check_name' declares more than one job-level name."
    fi
    if (( explicit_name_count == 1 )) && [[ "$explicit_names" != "$check_name" ]]; then
      fact_error "release gate" "$workflow" \
        "Job '$check_name' exposes check name '$explicit_names'; expected '$check_name'."
    fi
  done
}

main() {
  local marketing_version=""
  local build_number=""
  local package_version=""
  local package_revision=""

  require_command awk
  require_command grep
  require_command jq
  require_command sed

  require_file "marketing version and build number" "$PROJECT_SPEC"
  require_file "ZIPFoundation resolved revision" "$PACKAGE_LOCK"
  require_file "release gate" "$REQUIRED_CHECKS_SCRIPT"
  require_file "marketing version and build number" "$README"
  require_file "marketing version and build number" "$ROADMAP"
  require_file "ZIPFoundation dependency" "$THIRD_PARTY"
  require_file "public release checklist" "$PUBLIC_RELEASE_CHECKLIST"
  require_file "release gate" "$TESTFLIGHT_RELEASES"
  require_file "SwiftLint configuration" "$SWIFTLINT_CONFIG"

  marketing_version="$(yaml_scalar MARKETING_VERSION "marketing version")"
  build_number="$(yaml_scalar CURRENT_PROJECT_VERSION "build number")"
  package_version="$(zipfoundation_exact_version)"
  [[ "$marketing_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9]+)*$ ]] \
    || fact_error "marketing version" "$PROJECT_SPEC" \
      "MARKETING_VERSION is not a semantic version: $marketing_version"
  [[ "$build_number" =~ ^[1-9][0-9]*$ ]] \
    || fact_error "build number" "$PROJECT_SPEC" \
      "CURRENT_PROJECT_VERSION must be a positive integer: $build_number"
  [[ "$package_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9]+)*$ ]] \
    || fact_error "ZIPFoundation exact version" "$PROJECT_SPEC" \
      "ZIPFoundation exactVersion is not a semantic version: $package_version"

  if ! jq -e --arg version "$package_version" '
    .version == 3
    and (.pins | type == "array" and length == 1)
    and .pins[0].identity == "zipfoundation"
    and .pins[0].kind == "remoteSourceControl"
    and .pins[0].state.version == $version
    and (.pins[0].state.revision | type == "string" and test("^[0-9a-f]{40}$"))
  ' "$PACKAGE_LOCK" >/dev/null; then
    fact_error "ZIPFoundation resolved revision" "$PACKAGE_LOCK" \
      "Package.resolved must contain one ZIPFoundation pin matching project.yml's exactVersion with a full lowercase revision."
  fi
  package_revision="$(jq -r '.pins[0].state.revision' "$PACKAGE_LOCK")"

  require_literal "marketing version and build number" "$README" '[`project.yml`](project.yml)'
  require_literal "marketing version and build number" "$ROADMAP" '[`project.yml`](../project.yml)'
  reject_version_claims "$README"
  reject_version_claims "$ROADMAP"
  if grep -Eiq 'public release checklist[^[:cntrl:]]*stub' "$README"; then
    fact_error "public release checklist" "$README" \
      "The checklist is substantive and must not be labelled a stub."
  fi

  require_literal "ZIPFoundation exact version" "$THIRD_PARTY" '[`project.yml`](../project.yml)'
  require_literal "ZIPFoundation resolved revision" "$THIRD_PARTY" '[`Package.resolved`](../OpenTVTracker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved)'
  reject_dependency_claims "$THIRD_PARTY"
  require_literal "SwiftLint configuration" "$THIRD_PARTY" '[`.swiftlint.yml`](../.swiftlint.yml)'
  reject_literal "SwiftLint configuration" "$THIRD_PARTY" 'There is no `.swiftlint.yml`'

  require_literal "public release checklist" "$PUBLIC_RELEASE_CHECKLIST" \
    '[public release checklist](TESTFLIGHT_RELEASES.md#public-release-checklist)'
  require_literal "marketing version and build number" "$TESTFLIGHT_RELEASES" \
    '[`project.yml`](../project.yml)'
  require_literal "release gate" "$README" \
    '[`.github/scripts/required-checks.sh`](.github/scripts/required-checks.sh)'
  require_literal "release gate" "$TESTFLIGHT_RELEASES" \
    '[`.github/scripts/required-checks.sh`](../.github/scripts/required-checks.sh)'

  validate_release_contract

  printf 'Repository facts are consistent (app %s build %s; ZIPFoundation %s at %s).\n' \
    "$marketing_version" "$build_number" "$package_version" "$package_revision"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
