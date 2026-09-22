#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
validator="$repo_root/scripts/conventions/validate-pr.py"
workflow="$repo_root/.github/workflows/conventions.yml"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  printf 'conventions-contract: FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -f "$validator" ]] || fail "missing validator: scripts/conventions/validate-pr.py"
[[ -f "$workflow" ]] || fail "missing reusable workflow: .github/workflows/conventions.yml"

grep -Eq '^  workflow_call:$' "$workflow" \
  || fail "reusable workflow must expose workflow_call"
grep -Fq '      infrastructure:' "$workflow" \
  || fail "reusable workflow must expose the infrastructure input"
grep -Fq '  contents: read' "$workflow" \
  || fail "reusable workflow must grant contents read only"
grep -Fq '  pull-requests: read' "$workflow" \
  || fail "reusable workflow must grant pull requests read only"
grep -Eq '^[[:space:]]+uses: actions/checkout@[0-9a-f]{40}([[:space:]]+#.*)?$' "$workflow" \
  || fail "checkout action must use a full commit SHA"
if grep -Eq '^[[:space:]]+uses: [^#]+@(v[0-9]+|main|master)([[:space:]]+#.*)?$' "$workflow"; then
  fail "reusable workflow contains a mutable action reference"
fi
# The literal GitHub expression is the contract.
# shellcheck disable=SC2016
grep -Fq 'repository: ${{ job.workflow_repository }}' "$workflow" \
  || fail "reusable workflow must check out its own repository"
# The literal GitHub expression is the contract.
# shellcheck disable=SC2016
grep -Fq 'ref: ${{ job.workflow_sha }}' "$workflow" \
  || fail "reusable workflow must check out its own pinned revision"
grep -Fq 'python3 conventions-source/scripts/conventions/validate-pr.py' "$workflow" \
  || fail "reusable workflow must run the convention validator"

valid_body="$(cat <<'EOF'
## What changes

The workflow enforces the organization delivery contract.

## Why

Pull requests need deterministic validation before merge.

## Tasks

- [ ] ai-agents specs/001-governance-and-iac-program T009

## How it is verified

The contract test exercises every validation rule.

## Risk and rollback

Reverting the workflow removes the new required check.

## What this PR does not do

The change does not modify application delivery.

- [ ] Infrastructure changes: the documentation consulted through the required MCP servers is listed above
EOF
)"
checked_body="${valid_body/- \[ \] Infrastructure changes:/- [x] Infrastructure changes:}"

case_count=0

run_validator() {
  local title="$1"
  local branch="$2"
  local body="$3"
  local infrastructure="$4"
  local changed_files="$5"
  local files_path="$tmp_dir/changed-files.txt"

  printf '%b' "$changed_files" >"$files_path"
  env \
    PR_TITLE="$title" \
    PR_HEAD_BRANCH="$branch" \
    PR_BODY="$body" \
    INFRASTRUCTURE="$infrastructure" \
    CHANGED_FILES_FILE="$files_path" \
    python3 "$validator"
}

expect_pass() {
  local name="$1"
  shift
  local output

  if ! output="$(run_validator "$@" 2>&1)"; then
    fail "$name should pass; output: $output"
  fi
  [[ "$output" == *"conventions: PASS"* ]] \
    || fail "$name did not report the success marker"
  case_count=$((case_count + 1))
  printf 'PASS: %s\n' "$name"
}

expect_rejection() {
  local name="$1"
  local expected="$2"
  shift 2
  local output

  if output="$(run_validator "$@" 2>&1)"; then
    fail "$name should be rejected"
  fi
  [[ "$output" == *"$expected"* ]] \
    || fail "$name produced the wrong rejection: $output"
  case_count=$((case_count + 1))
  printf 'MUTATION: %s -> %s\n' "$name" "$expected"
}

for type in feat fix test docs chore ci promote; do
  expect_pass "allowed title type $type" \
    "$type(ci): enforce pull request conventions" \
    "$type/pull-request-conventions" "$valid_body" false "README.md\n"
done

expect_rejection "title without scope" "title must match" \
  "feat: enforce pull request conventions" \
  "feat/pull-request-conventions" "$valid_body" false "README.md\n"
expect_rejection "disallowed title type" "title must match" \
  "build(ci): enforce pull request conventions" \
  "feat/pull-request-conventions" "$valid_body" false "README.md\n"
expect_rejection "upper-case title summary" "summary must be lower case" \
  "feat(ci): Enforce pull request conventions" \
  "feat/pull-request-conventions" "$valid_body" false "README.md\n"
expect_rejection "title with trailing period" "summary must not end with a period" \
  "feat(ci): enforce pull request conventions." \
  "feat/pull-request-conventions" "$valid_body" false "README.md\n"
expect_rejection "non-imperative title summary" "summary must start with an imperative verb" \
  "feat(ci): implemented pull request conventions" \
  "feat/pull-request-conventions" "$valid_body" false "README.md\n"

expect_rejection "branch without type" "branch must match" \
  "feat(ci): enforce pull request conventions" \
  "pull-request-conventions" "$valid_body" false "README.md\n"
expect_rejection "branch with underscore" "branch must match" \
  "feat(ci): enforce pull request conventions" \
  "feat/pull_request_conventions" "$valid_body" false "README.md\n"
expect_rejection "branch with disallowed type" "branch must match" \
  "feat(ci): enforce pull request conventions" \
  "build/pull-request-conventions" "$valid_body" false "README.md\n"
expect_pass "Dependabot branch exemption" \
  "chore(deps): update dependency actions checkout to v5" \
  "dependabot/github_actions/actions/checkout-5" "$valid_body" false "README.md\n"
expect_pass "release-tool branch exemption" \
  "chore(release): prepare version 2 0 0" \
  "release-please--branches--main" "$valid_body" false "README.md\n"

for section in \
  "What changes" \
  "Why" \
  "Tasks" \
  "How it is verified" \
  "Risk and rollback" \
  "What this PR does not do"
do
  missing_body="$(
    awk -v target="## $section" \
      '$0 == target { $0 = "## Removed section" } { print }' <<<"$valid_body"
  )"
  expect_rejection "missing body section $section" "missing required body section: $section" \
    "feat(ci): enforce pull request conventions" \
    "feat/pull-request-conventions" "$missing_body" false "README.md\n"
done

comment_only_body="${valid_body/The workflow enforces the organization delivery contract./   <!-- template placeholder -->}"
expect_rejection "comment-only body section" "body section contains no substantive content: What changes" \
  "feat(ci): enforce pull request conventions" \
  "feat/pull-request-conventions" "$comment_only_body" false "README.md\n"

whitespace_only_body="${valid_body/The workflow enforces the organization delivery contract./   }"
expect_rejection "whitespace-only body section" "body section contains no substantive content: What changes" \
  "feat(ci): enforce pull request conventions" \
  "feat/pull-request-conventions" "$whitespace_only_body" false "README.md\n"

expect_rejection "unchecked Terraform documentation checkbox" \
  "infrastructure documentation checkbox must be checked" \
  "feat(ci): enforce pull request conventions" \
  "feat/pull-request-conventions" "$valid_body" true "modules/example/main.tf\n"
expect_rejection "unchecked tfvars documentation checkbox" \
  "infrastructure documentation checkbox must be checked" \
  "feat(ci): enforce pull request conventions" \
  "feat/pull-request-conventions" "$valid_body" true "environments/dev/dev.tfvars\n"
expect_rejection "unchecked Kubernetes documentation checkbox" \
  "infrastructure documentation checkbox must be checked" \
  "feat(ci): enforce pull request conventions" \
  "feat/pull-request-conventions" "$valid_body" true "clusters/dev/deployment.yaml\n"
expect_pass "checked infrastructure documentation checkbox" \
  "feat(ci): enforce pull request conventions" \
  "feat/pull-request-conventions" "$checked_body" true "modules/example/main.tf\n"

# The repositories' pull request templates print this line with a trailing
# reference: "... is listed above (`microservice-app-ai-agents/rules/mcp.md`)".
# A body that keeps the template's own wording must pass; the checkbox is the
# contract, not the absence of the reference the template itself supplies.
template_suffix_body="${checked_body/is listed above/is listed above (\`microservice-app-ai-agents/rules/mcp.md\`)}"
expect_pass "checked infrastructure checkbox with the template's trailing reference" \
  "feat(ci): enforce pull request conventions" \
  "feat/pull-request-conventions" "$template_suffix_body" true "modules/example/main.tf\n"

unchecked_suffix_body="${valid_body/is listed above/is listed above (\`microservice-app-ai-agents/rules/mcp.md\`)}"
expect_rejection "unchecked infrastructure checkbox with the template's trailing reference" \
  "infrastructure documentation checkbox must be checked" \
  "feat(ci): enforce pull request conventions" \
  "feat/pull-request-conventions" "$unchecked_suffix_body" true "modules/example/main.tf\n"
expect_pass "non-infrastructure repository ignores Terraform checkbox" \
  "feat(ci): enforce pull request conventions" \
  "feat/pull-request-conventions" "$valid_body" false "modules/example/main.tf\n"
expect_pass "workflow YAML is not a Kubernetes manifest" \
  "feat(ci): enforce pull request conventions" \
  "feat/pull-request-conventions" "$valid_body" true ".github/workflows/ci.yml\n"

printf 'conventions-contract: PASS (%s cases)\n' "$case_count"
