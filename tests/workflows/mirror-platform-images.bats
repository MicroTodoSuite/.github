#!/usr/bin/env bash
# Contract test for the platform-image mirror workflow (gitops spec 009 T082).
# Same grep-the-contract style as tests/ci-contract.sh: it asserts the workflow
# keeps the guarantees the task requires, and — just as important — that it does
# NOT reintroduce the things the task forbids (static credentials, the service
# publisher role, a hard-coded account). Executable bash, run directly; no bats
# framework, matching the repo's other contract tests.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow="$repo_root/.github/workflows/mirror-platform-images.yml"

fail() { echo "mirror-contract: $*" >&2; exit 1; }

[[ -f "$workflow" ]] || fail "workflow is missing: $workflow"

require_literal() {
  grep -Fq -- "$1" "$workflow" || fail "missing required contract literal: $1"
}
forbid_literal() {
  grep -Fq -- "$1" "$workflow" && fail "forbidden literal present: $1" || true
}
forbid_regex() {
  grep -Eq -- "$1" "$workflow" && fail "forbidden pattern present: $1" || true
}

# --- OIDC only, no static credentials --------------------------------------
require_literal "id-token: write"
require_literal "aws-actions/configure-aws-credentials@61815dcd50bd041e203e49132bacad1fd04d2708 # v5"
require_literal "role-to-assume:"
forbid_regex "aws_access_key_id|AWS_SECRET_ACCESS_KEY|AWS_ACCESS_KEY_ID"

# --- a DEDICATED mirror role, never the service publisher role --------------
require_literal "mirror-role-arn"
forbid_literal "microtodosuite-github-ecr-publisher"

# --- the destination is the parameterized platform ECR repository ----------
# Account comes from the org variable, never a hard-coded (retired) literal.
require_literal "vars.AWS_ACCOUNT_ID"
require_literal ".dkr.ecr."
require_literal "amazonaws.com"
require_literal "microtodosuite/platform"
forbid_literal "916491575487"
forbid_literal "995253610162"

# --- reads the locked image set, does not invent it ------------------------
require_literal "full-profile-toolchain.lock"
require_literal ".images"

# --- checksum-pinned tooling (crane, cosign, trivy) ------------------------
require_literal "sha256sum"
require_literal "--check"
require_literal "5c16d8ddb971cb1d5e6ed8b1e743da8224414eeba2c2762d8f1a61b2f095699e" # crane
require_literal "4629c757b7618056f8ddd7e2625ae9fdd94c0372a65049520bc7d9df9efc7f71" # cosign
require_literal "2ae6fe3ee734b7fdf11335663e18c75ea12dccc76062f09f164a3b0f8be4371a" # trivy

# --- copy the complete OCI graph without rebuilding, verify the digest -----
require_literal "crane copy"
require_literal "crane digest"
require_literal "upstreamDigest"
require_literal "mirrorTag"

# --- scan the mirrored image -----------------------------------------------
require_literal "trivy image"

# --- keyless-sign the complete graph ---------------------------------------
require_literal "cosign sign"
require_literal 'COSIGN_YES'

# --- record source and mirror digests as evidence --------------------------
require_literal "source"
require_literal "mirror"

# --- never checks out or references a service repository -------------------
for svc in microservice-app-auth-api microservice-app-todos-api \
           microservice-app-users-api microservice-app-frontend \
           microservice-app-log-message-processor; do
  forbid_literal "$svc"
done

echo "mirror-contract: OK — OIDC-only dedicated-role mirror, parameterized platform ECR, checksum-pinned crane/cosign/trivy, digest-preserving copy with verification, scan, keyless signature, no static creds and no service-repo access."
