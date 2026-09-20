#!/usr/bin/env bash
# Contract test for the reusable delivery workflows (gitops spec 009 T099).
# Same grep-the-contract style as tests/ci-contract.sh. Asserts the guarantees
# US4 requires across ci/release/promote — required coverage gates, Sonar
# fail-closed, digest-only output, OIDC with no static credentials, GitHub App
# tokens, exact destination tuples, SHA-pinned actions, and no cluster mutation
# — plus the five-service quality-gate matrix. Executable bash, run directly.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ci="$root/.github/workflows/ci.yml"
release="$root/.github/workflows/release.yml"
promote="$root/.github/workflows/promote.yml"
matrix="$root/tests/workflows/quality-gate-matrix.yaml"

fail() { echo "reusable-workflow-contract: $*" >&2; exit 1; }
have() { grep -Fq -- "$2" "$1" || fail "$3"; }
lacks() { grep -Fq -- "$2" "$1" && fail "$3" || true; }

for f in "$ci" "$release" "$promote" "$matrix"; do
  [[ -f "$f" ]] || fail "missing required file: $f"
done

# --- ci.yml: coverage gates, Sonar fail-closed, digest output, OIDC ---------
have "$ci" "workflow_call" "ci.yml must be a reusable workflow"
have "$ci" "test-command:" "ci.yml must take a required test-command gate"
have "$ci" "test-command must not be empty or blank" \
  "ci.yml must fail visibly on an empty test-command, never pass having tested nothing (FR-017, gitops spec 003 T024)"
have "$ci" "contract-command:" "ci.yml must take a contract-command gate"
have "$ci" "sonar-required:" "ci.yml must expose the Sonar fail-closed toggle (T102)"
have "$ci" "the SonarQube quality gate is required but not configured" \
  "ci.yml must fail closed when Sonar is required but unconfigured"
have "$ci" "image-digest:" "ci.yml must output the immutable image digest"
have "$ci" "aws-actions/configure-aws-credentials@61815dcd50bd041e203e49132bacad1fd04d2708" \
  "ci.yml must authenticate through pinned OIDC configure-aws-credentials"

# --- release.yml: short-lived GitHub App token, no static credentials -------
# The kebab-case secret inputs are the exact caller secrets T099 mandates:
# a caller wires RELEASE_APP_ID -> release-app-id, etc.
have "$release" "actions/create-github-app-token@d72941d797fd3113feb6b93fd0dec494b13a2547" \
  "release.yml must mint a short-lived GitHub App token by pinned SHA"
have "$release" "release-app-id:" "release.yml must take the RELEASE_APP_ID caller secret"
have "$release" "release-app-key:" "release.yml must take the RELEASE_APP_KEY caller secret"

# --- promote.yml: tuple validation, provenance, App token, one-overlay ------
have "$promote" "sha256:" "promote.yml must validate the sha256 digest format"
have "$promote" "cosign verify" "promote.yml must verify the image signature before promoting"
have "$promote" "unregistered profile/destination tuple" \
  "promote.yml must reject an unregistered profile/destination tuple (T104)"
have "$promote" "strategy:" "promote.yml must take a validated strategy input (T104)"
have "$promote" "canary is only valid for full/eks-full-prod" \
  "promote.yml must confine canary to full AWS production"
have "$promote" "actions/create-github-app-token@d72941d797fd3113feb6b93fd0dec494b13a2547" \
  "promote.yml must use the pinned GitHub App token"
have "$promote" "gitops-promote-app-id:" \
  "promote.yml must take the GITOPS_PROMOTE_APP_ID caller secret (T099)"
have "$promote" "gitops-promote-app-key:" \
  "promote.yml must take the GITOPS_PROMOTE_APP_KEY caller secret (T099)"
have "$promote" "bump-image.sh" "promote.yml must bump exactly one overlay via the digest-only helper"

# --- OIDC, no static credentials anywhere ----------------------------------
for f in "$ci" "$release" "$promote"; do
  if grep -Eq 'aws_access_key_id|AWS_SECRET_ACCESS_KEY|AWS_ACCESS_KEY_ID' "$f"; then
    fail "static AWS credentials present in $(basename "$f")"
  fi
done

# --- every `uses:` is pinned by full 40-hex SHA ----------------------------
for f in "$ci" "$release" "$promote"; do
  while IFS= read -r line; do
    # The ref is the first token after `uses:`, before any ` # version` comment.
    ref="$(sed -E 's/.*uses:[[:space:]]*//' <<<"$line" | awk '{print $1}')"
    [[ "$ref" == ./* ]] && continue                    # local reusable workflow
    [[ "$ref" =~ @[0-9a-f]{40}$ ]] \
      || fail "unpinned action in $(basename "$f"): $ref"
  done < <(grep -E '^\s*(-\s*)?uses:' "$f")
done

# --- no reusable workflow mutates a cluster --------------------------------
for f in "$ci" "$release" "$promote"; do
  if grep -Eq 'kubectl[[:space:]]+(apply|patch|delete|scale|replace|create)|kustomize[[:space:]]+build[^|]*\|[[:space:]]*kubectl' "$f"; then
    fail "cluster-mutating command in $(basename "$f")"
  fi
done

# --- the publication guard accepts the rebuilt names ------------------------
# ops spec 004 renames the registry and the publisher role. The guard must take
# the rebuilt names, and keep taking the legacy ones until that rebuild retires
# them, so a caller can move without breaking every push to its main.
guard_script() {
  awk -v step="      - name: $1" '
    $0 == step { in_step = 1; next }
    in_step && /^      - name: / { exit }
    in_step && /^        run: \|/ { in_run = 1; next }
    in_run && /^          / { sub(/^          /, ""); print; next }
    in_run && NF == 0 { print ""; next }
    in_run { exit }
  ' "$ci"
}

guard_accepts() {  # name, description, env assignments...
  local script=$1 description=$2; shift 2
  env "$@" bash -c "$script" >/dev/null 2>&1 \
    || fail "the publication guard must accept $description"
}

guard_rejects() {
  local script=$1 description=$2; shift 2
  if env "$@" bash -c "$script" >/dev/null 2>&1; then
    fail "the publication guard must reject $description"
  fi
}

inputs_guard="$(guard_script 'Validate immutable publication inputs')"
[[ -n "$inputs_guard" ]] || fail "could not read the publication input guard from ci.yml"
account=000000000000
registry="${account}.dkr.ecr.us-east-1.amazonaws.com"
guard_accepts "$inputs_guard" "the rebuilt repository of a service" \
  SERVICE_NAME=auth-api "ECR_REPOSITORY=${registry}/lex-mts-shd-ecr-authapi" \
  AWS_REGION_INPUT=us-east-1 "AWS_ACCOUNT_ID=${account}"
guard_accepts "$inputs_guard" "the legacy repository until the rebuild retires it" \
  SERVICE_NAME=auth-api "ECR_REPOSITORY=${registry}/microtodosuite/auth-api" \
  AWS_REGION_INPUT=us-east-1 "AWS_ACCOUNT_ID=${account}"
guard_rejects "$inputs_guard" "another service's repository" \
  SERVICE_NAME=auth-api "ECR_REPOSITORY=${registry}/lex-mts-shd-ecr-frontend" \
  AWS_REGION_INPUT=us-east-1 "AWS_ACCOUNT_ID=${account}"
guard_rejects "$inputs_guard" "a repository outside the account registry" \
  SERVICE_NAME=auth-api ECR_REPOSITORY=docker.io/someone/auth-api \
  AWS_REGION_INPUT=us-east-1 "AWS_ACCOUNT_ID=${account}"

boundary_guard="$(guard_script 'Validate reviewed-main publication boundary')"
[[ -n "$boundary_guard" ]] || fail "could not read the publication boundary guard from ci.yml"
guard_accepts "$boundary_guard" "the rebuilt publisher role" \
  "PUBLISHER_ROLE_ARN=arn:aws:iam::${account}:role/lex-mts-shd-role-ecrpublish" "AWS_ACCOUNT_ID=${account}"
guard_accepts "$boundary_guard" "the legacy publisher role until the rebuild retires it" \
  "PUBLISHER_ROLE_ARN=arn:aws:iam::${account}:role/microtodosuite-github-ecr-publisher" "AWS_ACCOUNT_ID=${account}"
guard_rejects "$boundary_guard" "any other role" \
  "PUBLISHER_ROLE_ARN=arn:aws:iam::${account}:role/someone-elses-role" "AWS_ACCOUNT_ID=${account}"

# --- five-service quality-gate matrix is complete --------------------------
for svc in auth-api todos-api users-api frontend log-message-processor; do
  grep -Eq "^\s{2}${svc}:" "$matrix" || fail "matrix is missing service: $svc"
done
for gate in unit integration contract e2e performance dast sonar; do
  grep -Eq "^\s{4}${gate}:" "$matrix" || fail "matrix is missing gate: $gate"
done

echo "reusable-workflow-contract: OK — ci/release/promote carry the required gates, Sonar fail-closed, digest-only output, OIDC with no static creds, SHA-pinned actions, validated destination tuples, no cluster mutation, and the five-service quality-gate matrix is complete."
