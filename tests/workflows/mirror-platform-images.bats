#!/usr/bin/env bash
# Contract test for the platform-image mirror workflow (gitops spec 009 T082).
# Same grep-the-contract style as tests/ci-contract.sh: it asserts the workflow
# keeps the guarantees the task requires, and — just as important — that it does
# NOT reintroduce the things the task forbids (static credentials, the service
# publisher role, a hard-coded account). Executable bash, run directly; no bats
# framework, matching the repo's other contract tests.
#
# Extended for gitops spec 009 T121 (for T131): after ACR exists, the same
# workflow copies the complete already-signed locked platform graph from the
# platform ECR repository to ACR without rebuilding or re-signing. research.md
# Decision 13 is the requirement: AWS and Azure through OIDC, the approved
# platform-mirror identity verified in ACR, and a missing image, mutable
# reference, signature, attestation or digest mismatch blocks activation. That
# half is checked statically on the `mirror-to-acr` job and behaviorally by
# running its copy step against mock registries, fully offline.
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

# ===========================================================================
# T121: the ECR -> ACR copy of the already-signed platform graph (for T131)
# ===========================================================================
self_test="$repo_root/.github/workflows/mirror-platform-images-self-test.yml"
[[ -f "$self_test" ]] || fail "self-test workflow is missing: $self_test"

step_script() {
  awk -v step="      - name: $2" '
    $0 == step { in_step = 1; next }
    in_step && /^      - name: / { exit }
    in_step && /^        run: \|/ { in_run = 1; next }
    in_run && /^          / { sub(/^          /, ""); print; next }
    in_run && NF == 0 { print ""; next }
    in_run { exit }
  ' "$1"
}

# --- nothing in this workflow builds an image -------------------------------
forbid_regex "Dockerfile|docker (build|push)|buildx|build-push-action|az acr build|az acr import|ko build|jib"

# --- every `uses:` is pinned by full 40-hex SHA -----------------------------
while IFS= read -r line; do
  ref="$(sed -E 's/.*uses:[[:space:]]*//' <<<"$line" | awk '{print $1}')"
  [[ "$ref" == ./* ]] && continue
  [[ "$ref" =~ @[0-9a-f]{40}$ ]] || fail "unpinned action: $ref"
done < <(grep -E '^\s*(-\s*)?uses:' "$workflow")

# --- no static Azure credential anywhere ------------------------------------
forbid_regex "creds:|client-secret|AZURE_CLIENT_SECRET|AZURE_CREDENTIALS|admin-enabled|--password|AWS_SESSION_TOKEN"

# --- the ACR destination and its Azure identity are inputs ------------------
for input in acr-name azure-client-id; do
  require_literal "      ${input}:"
done

acr_job="$(awk '/^  mirror-to-acr:/ { f = 1; next } f && /^  [a-z]/ { exit } f' "$workflow")"
[[ -n "$acr_job" ]] || fail "missing the mirror-to-acr job that copies the platform graph from ECR to ACR"
job_has() { grep -Fq -- "$1" <<<"$acr_job" || fail "mirror-to-acr job: missing $1"; }
job_forbids() { grep -Eq -- "$1" <<<"$acr_job" && fail "mirror-to-acr job: forbidden $1" || true; }

# Runs only when an ACR is named, so the EKS-only mirror is unchanged.
job_has "inputs.acr-name"

# AWS and Azure through OIDC; the ECR side is the approved platform-mirror role.
job_has "id-token: write"
job_has "aws-actions/configure-aws-credentials@61815dcd50bd041e203e49132bacad1fd04d2708"
job_has "microtodosuite-platform-mirror"
job_has "azure/login@a641126d1b8aa4d1fa005f4f92df94a3a4c4c906"
job_has "inputs.azure-client-id"
job_has "az acr login"
job_forbids "microtodosuite-github-ecr-publisher"

# The source is the already-signed platform ECR repository, from the lock.
job_has "vars.AWS_ACCOUNT_ID"
job_has "microtodosuite/platform"
job_has "full-profile-toolchain.lock"

# Copied recursively with its referrers; never rebuilt and never re-signed:
# the ECR signature is the one Kyverno admits, so ACR must carry that one.
job_has "oras cp -r"
job_has "crane digest"
job_has ".sig"
job_has ".att"
job_has ".sbom"
job_forbids "cosign (sign|attest|attach)"
job_forbids "crane (mutate|append|rebase|flatten)"

# Checksum-locked oras from the toolchain lock, like the service mirror.
job_has "sha256sum --check --strict"
job_has 'select(.name == "oras")'

# Verified in ACR against the platform-mirror identity, not the service CI one.
job_has "cosign verify "
job_has '^https://github\.com/MicroTodoSuite/\.github/\.github/workflows/mirror-platform-images\.yml@'
job_has "--certificate-oidc-issuer https://token.actions.githubusercontent.com"
job_forbids 'workflows/ci(\\)?\.yml'

# --- behavior: copy every locked image and prove digest equality, offline ---
copy="$(step_script "$workflow" "Copy the signed platform graph from ECR to ACR without rebuilding")"
[[ -n "$copy" ]] || fail "could not read the ECR-to-ACR copy step"

sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

hexof() { printf "${1}%.0s" {1..64}; }
d_argo="sha256:$(hexof a)"
d_kyv="sha256:$(hexof b)"
d_other="sha256:$(hexof e)"
d_sig="sha256:$(hexof c)"
d_att="sha256:$(hexof d)"
ecr_repo="000000000000.dkr.ecr.us-east-1.amazonaws.com/microtodosuite/platform"
acr_server="mtsdrtest.azurecr.io"
acr_repo="$acr_server/microtodosuite/platform"

write_lock() {
  mkdir -p "$sandbox/gitops/scripts/managed"
  jq -n --arg a "$1" --arg k "$2" '{images: [
    {id: "argocd",  upstreamRef: "quay.io/argoproj/argocd:v3.5.0",       upstreamDigest: $a, mirrorTag: "argocd-3.5.0"},
    {id: "kyverno", upstreamRef: "ghcr.io/kyverno/kyverno:v1.15.0",      upstreamDigest: $k, mirrorTag: "kyverno-1.15.0"}
  ]}' > "$sandbox/gitops/scripts/managed/full-profile-toolchain.lock"
}

mkdir -p "$sandbox/bin"
# crane: digests in ECR are the lock's; ACR echoes them unless told otherwise.
# argocd carries tag-scheme .sig and .att; nothing carries a tag-scheme .sbom.
cat > "$sandbox/bin/crane" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
echo "crane $*" >> "$SANDBOX/calls"
[[ "$1" == digest ]] || { echo "mock crane: only digest is expected, got $1" >&2; exit 3; }
ref="$2"; ha="${D_ARGO#sha256:}"; hk="${D_KYV#sha256:}"
case "$ref" in
  "$ECR_REPO@$D_ARGO"|"$ECR_REPO:argocd-3.5.0") echo "$D_ARGO" ;;
  "$ECR_REPO@$D_KYV"|"$ECR_REPO:kyverno-1.15.0")
    [[ "${MOCK_MISSING:-}" == kyverno ]] && { echo "MANIFEST_UNKNOWN" >&2; exit 1; }
    echo "$D_KYV" ;;
  "$ECR_REPO:sha256-$ha.sig") echo "$D_SIG" ;;
  "$ECR_REPO:sha256-$ha.att") echo "$D_ATT" ;;
  "$ACR_REPO:sha256-$ha.sig") echo "${MOCK_ACR_SIG:-$D_SIG}" ;;
  "$ACR_REPO:sha256-$ha.att") echo "${MOCK_ACR_ATT:-$D_ATT}" ;;
  "$ECR_REPO:sha256-$ha.sbom"|"$ECR_REPO:sha256-$hk."*) echo "MANIFEST_UNKNOWN" >&2; exit 1 ;;
  "$ACR_REPO:argocd-3.5.0"|"$ACR_REPO@$D_ARGO") echo "${MOCK_ACR_ARGO:-$D_ARGO}" ;;
  "$ACR_REPO:kyverno-1.15.0"|"$ACR_REPO@$D_KYV") echo "$D_KYV" ;;
  *) echo "mock crane: unexpected reference $ref" >&2; exit 3 ;;
esac
MOCK
cat > "$sandbox/bin/oras" <<'MOCK'
#!/usr/bin/env bash
echo "oras $*" >> "$SANDBOX/calls"
[[ "${MOCK_MISSING:-}" == kyverno && "$*" == *"$D_KYV"* ]] && { echo "not found" >&2; exit 1; }
exit 0
MOCK
cat > "$sandbox/bin/cosign" <<'MOCK'
#!/usr/bin/env bash
echo "cosign $*" >> "$SANDBOX/calls"
[[ "$1" == verify* ]] || { echo "mock cosign: $1 is forbidden in the ACR copy" >&2; exit 3; }
exit 0
MOCK
# Anything that would build, push outside oras, or reach the network fails.
for tool in docker podman buildah curl wget; do
  printf '#!/usr/bin/env bash\necho "%s $*" >> "$SANDBOX/calls"\necho "mock: %s is forbidden offline" >&2\nexit 9\n' \
    "$tool" "$tool" > "$sandbox/bin/$tool"
done
chmod +x "$sandbox/bin/"*

copy_run() {
  : > "$sandbox/calls"; : > "$sandbox/output"
  mkdir -p "$sandbox/tmp"
  env "$@" PATH="$sandbox/bin:$PATH" SANDBOX="$sandbox" \
    ECR_REPO="$ecr_repo" ACR_REPO="$acr_repo" \
    D_ARGO="$d_argo" D_KYV="$d_kyv" D_SIG="$d_sig" D_ATT="$d_att" \
    LOCK_PATH="$sandbox/gitops/scripts/managed/full-profile-toolchain.lock" \
    PLATFORM_REPOSITORY="$ecr_repo" ACR_LOGIN_SERVER="$acr_server" \
    RUNNER_TEMP="$sandbox/tmp" GITHUB_OUTPUT="$sandbox/output" \
    bash -c "$copy" >/dev/null 2>"$sandbox/stderr"
}

ha="${d_argo#sha256:}"
write_lock "$d_argo" "$d_kyv"
copy_run || { cat "$sandbox/stderr" >&2; fail "the ACR copy failed against equal-digest mocks"; }

# Every locked image, by digest from the platform ECR repository, never upstream.
grep -Fxq "oras cp -r $ecr_repo@$d_argo $acr_repo:argocd-3.5.0" "$sandbox/calls" \
  || fail "argocd must be copied recursively by digest from platform ECR to ACR"
grep -Fxq "oras cp -r $ecr_repo@$d_kyv $acr_repo:kyverno-1.15.0" "$sandbox/calls" \
  || fail "kyverno must be copied recursively by digest from platform ECR to ACR (the complete lock)"
grep -Eq "quay\.io|ghcr\.io|docker\.io" "$sandbox/calls" \
  && fail "the ACR copy must read the already-signed ECR mirror, never the upstream registry" || true

# Tag-scheme signature and attestation travel with the image; absent ones are skipped.
grep -Fxq "oras cp -r $ecr_repo:sha256-$ha.sig $acr_repo:sha256-$ha.sig" "$sandbox/calls" \
  || fail "the platform-mirror signature must be copied with the image"
grep -Fxq "oras cp -r $ecr_repo:sha256-$ha.att $acr_repo:sha256-$ha.att" "$sandbox/calls" \
  || fail "a tag-scheme attestation must be copied with the image"
grep -Fq "sha256-$ha.sbom $acr_repo" "$sandbox/calls" \
  && fail "an absent tag-scheme SBOM must be skipped, not invented" || true

# Equality is proven by reading the ACR side, for the image and its signature.
grep -Fq "crane digest $acr_repo" "$sandbox/calls" \
  || fail "the ACR manifest digest must be read back and compared"
grep -Fxq "crane digest $acr_repo:sha256-$ha.sig" "$sandbox/calls" \
  || fail "the copied signature digest must be read back from ACR and compared"

# Nothing was built, re-signed, or fetched from the network.
grep -Eq "^(docker|podman|buildah|curl|wget) " "$sandbox/calls" \
  && fail "the ACR copy must not build or reach the network" || true
grep -Eq "^cosign (sign|attest|attach)" "$sandbox/calls" \
  && fail "the ACR copy must never re-sign: the ECR signature is the admitted one" || true

# --- each broken guarantee blocks the copy ----------------------------------
copy_run "MOCK_ACR_ARGO=$d_other" \
  && fail "a different ACR manifest digest must fail the mirror" || true
copy_run "MOCK_ACR_SIG=$d_other" \
  && fail "a different ACR signature digest must fail the mirror" || true
copy_run "MOCK_ACR_ATT=$d_other" \
  && fail "a different ACR attestation digest must fail the mirror" || true
copy_run MOCK_MISSING=kyverno \
  && fail "a locked image missing from the platform ECR repository must fail the mirror" || true

write_lock "$d_argo" "latest"
copy_run && fail "a mutable (non-digest) lock reference must fail the mirror" || true
# The whole lock is validated first, so a bad entry leaves ACR untouched.
grep -q '^oras ' "$sandbox/calls" \
  && fail "a mutable lock reference must be rejected before any copy" || true

write_lock "$d_argo" "$d_kyv"
jq '.images = []' "$sandbox/gitops/scripts/managed/full-profile-toolchain.lock" > "$sandbox/empty.lock"
mv "$sandbox/empty.lock" "$sandbox/gitops/scripts/managed/full-profile-toolchain.lock"
copy_run && fail "an empty locked image set must fail rather than mirror nothing" || true

# --- the self-test runs this contract on every change that could break it ---
for path in \
  ".github/workflows/mirror-platform-images.yml" \
  ".github/workflows/mirror-platform-images-self-test.yml" \
  "tests/workflows/mirror-platform-images.bats"; do
  grep -Fq -- "$path" "$self_test" || fail "the self-test must run on changes to $path"
done

echo "mirror-contract: OK — OIDC-only dedicated-role mirror, parameterized platform ECR, checksum-pinned crane/cosign/trivy, digest-preserving copy with verification, scan, keyless signature, no static creds and no service-repo access; plus the ECR-to-ACR copy of the complete already-signed locked platform graph over AWS/Azure OIDC, no build and no re-signature, SHA-pinned actions, equal image/signature/attestation digests, and the platform-mirror identity verified in ACR."
