#!/usr/bin/env bash
# Markdown fixture literals intentionally keep backticks inert.
# shellcheck disable=SC2016
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
readonly ROOT
readonly SCRIPT="$ROOT/.github/scripts/repository-facts.sh"

TMP="$(mktemp -d)"
readonly TMP
trap 'rm -rf "$TMP"' EXIT

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

make_fixture() {
  local name="$1"
  local fixture="$TMP/$name"
  local path=""
  local -a paths=(
    .swiftlint.yml
    .github/scripts/required-checks.sh
    .github/scripts/run-swiftlint.sh
    .github/workflows/ios.yml
    .github/workflows/secret-scan.yml
    .github/workflows/server.yml
    OpenTVTracker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
    CONTRIBUTING.md
    README.md
    docs/PUBLIC_RELEASE_CHECKLIST.md
    docs/ROADMAP.md
    docs/TESTFLIGHT_RELEASES.md
    docs/THIRD_PARTY_LICENSES.md
    project.yml
  )

  for path in "${paths[@]}"; do
    mkdir -p "$fixture/$(dirname "$path")"
    cp "$ROOT/$path" "$fixture/$path"
  done
  printf '%s\n' "$fixture"
}

run_checker() {
  local fixture="$1"
  set +e
  run_output="$(OPENTV_REPOSITORY_ROOT="$fixture" "$SCRIPT" 2>&1)"
  run_status=$?
  set -e
}

expect_success() {
  local label="$1"
  local fixture="$2"
  run_checker "$fixture"
  if (( run_status == 0 )); then
    pass "$label"
  else
    fail "$label returned $run_status: $run_output"
  fi
}

expect_failure() {
  local label="$1"
  local fixture="$2"
  local expected_file="$3"
  local expected_fact="$4"
  run_checker "$fixture"
  if (( run_status == 0 )); then
    fail "$label unexpectedly succeeded"
  elif [[ "$run_output" != *"file=$expected_file"* ]]; then
    fail "$label omitted file diagnostic '$expected_file': $run_output"
  elif [[ "$run_output" != *"Repository fact ($expected_fact)"* ]]; then
    fail "$label omitted fact diagnostic '$expected_fact': $run_output"
  else
    pass "$label"
  fi
}

fixture="$(make_fixture exact-repository)"
expect_success "accepts the exact repository facts" "$fixture"

fixture="$(make_fixture stale-readme-build)"
printf '\nBuild number **6**.\n' >> "$fixture/README.md"
expect_failure "rejects a stale README build" "$fixture" "README.md" "build number"

fixture="$(make_fixture natural-stale-readme-facts)"
printf '\nThe marketing version is 9.9.9 and the build number is 999.\n' >> "$fixture/README.md"
expect_failure "rejects natural stale README facts" "$fixture" "README.md" "marketing version"

fixture="$(make_fixture unrelated-build-prose)"
printf '\nA future benchmark may build 10 targets in parallel.\n' >> "$fixture/README.md"
expect_success "allows unrelated prose containing build and a number" "$fixture"

fixture="$(make_fixture marketing-version-example-prose)"
printf '\nA future guide may explain marketing version examples such as 1.2.3.\n' >> "$fixture/README.md"
expect_success "allows a marketing-version example" "$fixture"

fixture="$(make_fixture build-number-example-prose)"
printf '\nA future guide may explain build number examples such as 10.\n' >> "$fixture/README.md"
expect_success "allows a build-number example" "$fixture"

fixture="$(make_fixture stale-roadmap-version)"
printf '\nMarketing version 0.1.1.\n' >> "$fixture/docs/ROADMAP.md"
expect_failure "rejects a duplicated roadmap version" "$fixture" "docs/ROADMAP.md" "marketing version"

fixture="$(make_fixture stale-readme-stub)"
printf '\nPublic release checklist (stub).\n' >> "$fixture/README.md"
expect_failure "rejects a stale checklist label" "$fixture" "README.md" "public release checklist"

fixture="$(make_fixture missing-readme-owner)"
perl -0pi -e 's/\[`project\.yml`\]\(project\.yml\)/project.yml/g' "$fixture/README.md"
expect_failure "requires the README build owner link" "$fixture" "README.md" "marketing version and build number"

fixture="$(make_fixture duplicated-package-version)"
printf '\nZIPFoundation 0.8.0 remains pinned.\n' >> "$fixture/docs/THIRD_PARTY_LICENSES.md"
expect_failure "rejects a stale package version" "$fixture" "docs/THIRD_PARTY_LICENSES.md" "ZIPFoundation exact version"

fixture="$(make_fixture package-toolchain-example-prose)"
printf '\nA future guide may describe whether ZIPFoundation supports Xcode 26.4.1.\n' >> "$fixture/docs/THIRD_PARTY_LICENSES.md"
expect_success "allows an unrelated ZIPFoundation toolchain example" "$fixture"

fixture="$(make_fixture duplicated-package-revision)"
printf '\nPinned package revision: 0000000000000000000000000000000000000000.\n' >> "$fixture/docs/THIRD_PARTY_LICENSES.md"
expect_failure "rejects a stale package revision" "$fixture" "docs/THIRD_PARTY_LICENSES.md" "ZIPFoundation resolved revision"

fixture="$(make_fixture natural-stale-package-revision)"
printf '\nZIPFoundation is resolved to 0000000000000000000000000000000000000000.\n' >> "$fixture/docs/THIRD_PARTY_LICENSES.md"
expect_failure "rejects a natural stale package revision" "$fixture" "docs/THIRD_PARTY_LICENSES.md" "ZIPFoundation resolved revision"

fixture="$(make_fixture unrelated-revision-prose)"
printf '\nAn unrelated fixture commit is 0000000000000000000000000000000000000000.\n' >> "$fixture/docs/THIRD_PARTY_LICENSES.md"
expect_success "allows an unrelated full commit identifier" "$fixture"

fixture="$(make_fixture stale-swiftlint-claim)"
printf '\nThere is no `.swiftlint.yml`.\n' >> "$fixture/docs/THIRD_PARTY_LICENSES.md"
expect_failure "rejects a stale SwiftLint claim" "$fixture" "docs/THIRD_PARTY_LICENSES.md" "SwiftLint configuration"

fixture="$(make_fixture stale-swiftlint-ci-claim)"
printf '\nSwiftLint is not a required CI job.\n' >> "$fixture/docs/THIRD_PARTY_LICENSES.md"
expect_failure "rejects a stale SwiftLint CI claim" "$fixture" "docs/THIRD_PARTY_LICENSES.md" "SwiftLint CI gate"

fixture="$(make_fixture missing-swiftlint-doc-owner)"
perl -0pi -e 's/\[`\.github\/scripts\/run-swiftlint\.sh`\]\(\.\.\/\.github\/scripts\/run-swiftlint\.sh\)/.github\/scripts\/run-swiftlint.sh/g' \
  "$fixture/docs/THIRD_PARTY_LICENSES.md"
expect_failure "requires the SwiftLint license owner link" "$fixture" "docs/THIRD_PARTY_LICENSES.md" "SwiftLint CI gate"

fixture="$(make_fixture stale-contributing-swiftlint-claim)"
printf '\nThere is no SwiftLint job.\n' >> "$fixture/CONTRIBUTING.md"
expect_failure "rejects a stale contributing SwiftLint claim" "$fixture" "CONTRIBUTING.md" "SwiftLint CI gate"

fixture="$(make_fixture wrong-swiftlint-version)"
perl -0pi -e 's/readonly SWIFTLINT_VERSION="0\.65\.0"/readonly SWIFTLINT_VERSION="0.64.0"/' \
  "$fixture/.github/scripts/run-swiftlint.sh"
expect_failure "rejects a different SwiftLint version" "$fixture" ".github/scripts/run-swiftlint.sh" "SwiftLint CI gate"

fixture="$(make_fixture malformed-swiftlint-checksum)"
perl -0pi -e 's/readonly SWIFTLINT_ARCHIVE_SHA256="[0-9a-f]+"/readonly SWIFTLINT_ARCHIVE_SHA256="not-a-sha256"/' \
  "$fixture/.github/scripts/run-swiftlint.sh"
expect_failure "rejects a malformed SwiftLint checksum" "$fixture" ".github/scripts/run-swiftlint.sh" "SwiftLint CI gate"

fixture="$(make_fixture unapproved-swiftlint-checksum)"
perl -0pi -e 's/readonly SWIFTLINT_ARCHIVE_SHA256="[0-9a-f]+"/readonly SWIFTLINT_ARCHIVE_SHA256="0000000000000000000000000000000000000000000000000000000000000000"/' \
  "$fixture/.github/scripts/run-swiftlint.sh"
expect_failure "rejects an unapproved SwiftLint checksum" "$fixture" ".github/scripts/run-swiftlint.sh" "SwiftLint CI gate"

fixture="$(make_fixture missing-swiftlint-workflow-gate)"
perl -0pi -e 's/\.github\/scripts\/run-swiftlint\.sh/.github\/scripts\/missing-swiftlint.sh/' \
  "$fixture/.github/workflows/ios.yml"
expect_failure "requires SwiftLint in the existing iOS job" "$fixture" ".github/workflows/ios.yml" "SwiftLint CI gate"

fixture="$(make_fixture commented-swiftlint-workflow-gate)"
perl -0pi -e 's/^        run: \.github\/scripts\/run-swiftlint\.sh$/        # run: .github\/scripts\/run-swiftlint.sh/m' \
  "$fixture/.github/workflows/ios.yml"
expect_failure "rejects a commented-out SwiftLint workflow gate" "$fixture" ".github/workflows/ios.yml" "SwiftLint CI gate"

fixture="$(make_fixture job-environment-swiftlint-lookalike)"
perl -0pi -e 's/^      - name: Enforce pinned SwiftLint\n        run: \.github\/scripts\/run-swiftlint\.sh\n//m' \
  "$fixture/.github/workflows/ios.yml"
perl -0pi -e 's/^    timeout-minutes: 45$/    timeout-minutes: 45\n    env:\n      run: .github\/scripts\/run-swiftlint.sh/m' \
  "$fixture/.github/workflows/ios.yml"
expect_failure "rejects a job environment SwiftLint lookalike" "$fixture" ".github/workflows/ios.yml" "SwiftLint CI gate"

fixture="$(make_fixture mismatched-lock-version)"
lock="$fixture/OpenTVTracker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
jq '.pins[0].state.version = "99.0.0"' "$lock" > "$lock.next"
mv "$lock.next" "$lock"
expect_failure "rejects a lock version outside project.yml" "$fixture" "OpenTVTracker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" "ZIPFoundation resolved revision"

fixture="$(make_fixture malformed-lock-revision)"
lock="$fixture/OpenTVTracker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
jq '.pins[0].state.revision = "not-a-full-revision"' "$lock" > "$lock.next"
mv "$lock.next" "$lock"
expect_failure "rejects a malformed resolved revision" "$fixture" "OpenTVTracker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" "ZIPFoundation resolved revision"

fixture="$(make_fixture duplicate-build-owner)"
printf '\n# duplicate fixture\nCURRENT_PROJECT_VERSION: 11\n' >> "$fixture/project.yml"
expect_failure "rejects duplicate build owners" "$fixture" "project.yml" "build number"

fixture="$(make_fixture misplaced-package-owner)"
perl -0pi -e 's/exactVersion: 0\.9\.20/from: 0.9.20/' "$fixture/project.yml"
perl -0pi -e 's/packages:\n/packages:\n  OtherPackage:\n    url: https:\/\/example.invalid\/other-package\n    exactVersion: 0.9.20\n/' \
  "$fixture/project.yml"
expect_failure "rejects exactVersion owned by another package" "$fixture" "project.yml" "ZIPFoundation exact version"

fixture="$(make_fixture second-exact-package)"
perl -0pi -e 's/packages:\n/packages:\n  OtherPackage:\n    url: https:\/\/example.invalid\/other-package\n    exactVersion: 1.2.3\n/' \
  "$fixture/project.yml"
expect_success "allows a second package with its own exactVersion" "$fixture"

fixture="$(make_fixture stale-required-check)"
perl -0pi -e "s/\\.github\\/workflows\\/ios\\.yml\|build-and-test/.github\\/workflows\\/ios.yml|stale-build/" \
  "$fixture/.github/scripts/required-checks.sh"
expect_failure "rejects a required check missing from its workflow" "$fixture" ".github/workflows/ios.yml" "release gate"

fixture="$(make_fixture renamed-required-job)"
perl -0pi -e 's/^    name: build-and-test$/    name: renamed-build/m' \
  "$fixture/.github/workflows/ios.yml"
expect_failure "rejects a workflow check-name drift" "$fixture" ".github/workflows/ios.yml" "release gate"

fixture="$(make_fixture stale-checklist-redirect)"
perl -0pi -e 's/#public-release-checklist/#removed-checklist/' \
  "$fixture/docs/PUBLIC_RELEASE_CHECKLIST.md"
expect_failure "rejects a stale checklist redirect" "$fixture" "docs/PUBLIC_RELEASE_CHECKLIST.md" "public release checklist"

fixture="$(make_fixture missing-testflight-owner)"
perl -0pi -e 's/\[`project\.yml`\]\(\.\.\/project\.yml\)/project.yml/g' \
  "$fixture/docs/TESTFLIGHT_RELEASES.md"
expect_failure "requires the TestFlight build owner link" "$fixture" "docs/TESTFLIGHT_RELEASES.md" "marketing version and build number"

if (( failures > 0 )); then
  echo "$failures assertion(s) failed" >&2
  exit 1
fi
echo "All repository-facts assertions passed."
