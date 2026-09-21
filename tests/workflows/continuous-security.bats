#!/usr/bin/env bash
# Contract test for the scheduled continuous-security workflow (gitops spec 009
# T143, for T146). Same grep-the-contract style as
# tests/workflows/mirror-platform-images.bats: it asserts the guarantees the
# task requires and, just as important, that the workflow does NOT reintroduce
# what it forbids (static credentials, a mutating cluster verb, an unpinned
# action). Executable bash, run directly; no bats framework, matching the
# repository's other contract tests.
#
# FR-035 is the requirement behind it: running artifacts and their host
# environments are assessed continuously for newly disclosed vulnerabilities,
# and an actionable finding is routed into the review process rather than left
# in a log nobody reads.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow="$repo_root/.github/workflows/continuous-security.yml"
self_test="$repo_root/.github/workflows/continuous-security-self-test.yml"

fail() { echo "continuous-security-contract: $*" >&2; exit 1; }

[[ -f "$workflow" ]] || fail "workflow is missing: $workflow"
[[ -f "$self_test" ]] || fail "self-test workflow is missing: $self_test"

require_literal() {
  grep -Fq -- "$1" "$workflow" || fail "missing required contract literal: $1"
}
forbid_literal() {
  grep -Fq -- "$1" "$workflow" && fail "forbidden literal present: $1" || true
}
forbid_regex() {
  grep -Eq -- "$1" "$workflow" && fail "forbidden pattern present: $1" || true
}

# --- reusable, and schedulable by its callers -------------------------------
# The schedule lives in each caller, not here: GitHub never fires `schedule` for
# a reusable workflow, so a cron in this file would silently never run.
# Matched as a YAML key on its own line, not as text: the header explains the
# rule in prose, and forbidding the bare word would report that explanation.
require_literal "workflow_call"
require_literal "workflow_dispatch"
grep -Eq '^[[:space:]]*schedule:' "$workflow" \
  && fail "the reusable workflow must not declare a schedule; its callers do" || true

# --- the three surfaces T146 names ------------------------------------------
# Source: the caller's own checkout, every run, needing no credential.
require_literal "aquasecurity/trivy-action@57a97c7e7821a5776cebc9bb87c984fa69cba8f1"
require_literal "scan-type: fs"
require_literal "HIGH,CRITICAL"

# Image: the digests the GitOps repository declares for this service, which is
# what "running artifact" means here, read through a read-only App token, the
# same way mirror-platform-images.yml reads the locked image set.
require_literal "service-name"
require_literal "image-reader-role-arn"
require_literal "actions/create-github-app-token@d72941d797fd3113feb6b93fd0dec494b13a2547"
require_literal "microservice-app-gitops"
require_literal "profiles"
# Scanned by the checksum-locked Trivy release the toolchain lock records, not
# by the action: the set of declared digests is resolved at run time and an
# action cannot iterate it.
require_literal "trivy image"
require_literal "2ae6fe3ee734b7fdf11335663e18c75ea12dccc76062f09f164a3b0f8be4371a"
require_literal "sha256sum"
require_literal "--check"

# Cluster: the lane's existing read-only collector, never a new imperative path.
require_literal "verify-security.sh"

# --- every surface reports PASS, FAIL or BLOCKED, never a silent skip -------
# A surface with no credentials is BLOCKED and says so; it is never counted as
# a pass, and it never fails the run as though the platform were broken.
require_literal "BLOCKED"
require_literal "PASS"
require_literal "FAIL"

# --- actionable routing: one issue, in the repository that owns the artifact -
require_literal "issues: write"
require_literal "gh issue"
require_literal "continuous-security"

# --- a recurring finding updates its issue instead of opening a new one -----
# Without this a daily schedule files the same CVE 365 times and the signal is
# lost in its own noise.
require_literal "--state open"
require_literal "gh issue comment"

# --- a run that finds nothing closes the issue it opened --------------------
require_literal "gh issue close"

# --- OIDC only, no static credentials anywhere ------------------------------
require_literal "id-token: write"
require_literal "aws-actions/configure-aws-credentials@61815dcd50bd041e203e49132bacad1fd04d2708"
forbid_regex "aws_access_key_id|AWS_SECRET_ACCESS_KEY|AWS_ACCESS_KEY_ID"

# --- the registry is an input, so no account lives in this file -------------
# ci.yml already takes `ecr-repository` from its caller; the same shape here
# means this workflow holds no account at all, and no retired one can rot in it.
require_literal "image-repository"
forbid_literal "916491575487"
forbid_literal "995253610162"
forbid_regex "[0-9]{12}\.dkr\.ecr\."

# --- read-only: this workflow assesses, it never changes a cluster ----------
if grep -Eq 'kubectl[[:space:]]+(apply|patch|delete|scale|replace|create|edit|annotate|label)' "$workflow"; then
  fail "cluster-mutating kubectl verb present"
fi

# --- every `uses:` is pinned by full 40-hex SHA -----------------------------
while IFS= read -r line; do
  ref="$(sed -E 's/.*uses:[[:space:]]*//' <<<"$line" | awk '{print $1}')"
  [[ "$ref" == ./* ]] && continue
  [[ "$ref" =~ @[0-9a-f]{40}$ ]] || fail "unpinned action: $ref"
done < <(grep -E '^\s*(-\s*)?uses:' "$workflow")

# --- the self-test runs this contract on every change that could break it ---
for path in \
  ".github/workflows/continuous-security.yml" \
  ".github/workflows/continuous-security-self-test.yml" \
  "tests/workflows/continuous-security.bats"; do
  grep -Fq -- "$path" "$self_test" \
    || fail "the self-test must run on changes to $path"
done
grep -Fq "tests/workflows/continuous-security.bats" "$self_test" \
  || fail "the self-test must execute this contract"

echo "continuous-security-contract: OK: reusable and caller-scheduled, source/image/cluster surfaces with explicit PASS/FAIL/BLOCKED, digests read from GitOps through a read-only App token, findings routed to one deduplicated issue in the owning repository, OIDC with no static credentials, SHA-pinned actions, and no cluster mutation."
