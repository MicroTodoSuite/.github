#!/usr/bin/env bash
# Contract test for the disaster-recovery service mirror (gitops spec 009 T121,
# for T131) and its integration into promote.yml. Same grep-the-contract style
# as tests/workflows/mirror-platform-images.bats, plus a behavioral half: the
# production-validation guard, the copy step and promote.yml's tuple guard are
# read out of the workflows and run against mock registries and a fake GitOps
# tree. Executable bash, run directly; no bats framework, matching the
# repository's other contract tests.
#
# research.md Decision 13 and release-promotion-contract.md rules 8 and 9 are
# the requirements: only a production-validated digest advances to DR; the DR
# job copies the complete OCI graph (manifest, layers, signature, attestation,
# SBOM) from ECR to ACR without a build, verifies the signature and attestation
# in ACR, and fails unless both manifest digests are equal.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow="$repo_root/.github/workflows/mirror-to-acr.yml"
promote="$repo_root/.github/workflows/promote.yml"
self_test="$repo_root/.github/workflows/mirror-to-acr-self-test.yml"

fail() { echo "mirror-to-acr-contract: $*" >&2; exit 1; }

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

# --- reusable, with the artifact identity as its input ----------------------
require_literal "workflow_call"
for input in service-name image-digest image-ref ecr-reader-role-arn acr-name azure-client-id; do
  require_literal "      ${input}:"
done
require_literal "acr-image-ref"

# --- OIDC only, no static credential ----------------------------------------
require_literal "id-token: write"
require_literal "aws-actions/configure-aws-credentials@61815dcd50bd041e203e49132bacad1fd04d2708"
require_literal "aws-actions/amazon-ecr-login@03f1aad4c6c7ffd436567f42f9384779290529bd"
require_literal "azure/login@a641126d1b8aa4d1fa005f4f92df94a3a4c4c906"
require_literal "az acr login"
forbid_regex "aws_access_key_id|AWS_SECRET_ACCESS_KEY|AWS_ACCESS_KEY_ID|AWS_SESSION_TOKEN"
forbid_regex "creds:|client-secret|AZURE_CLIENT_SECRET|AZURE_CREDENTIALS|admin-enabled|--password"
grep -Eq '^[[:space:]]*secrets:' "$workflow" \
  && fail "the mirror must take no caller secret; it authenticates through OIDC alone" || true
# The public GitOps repository is read without any token.
require_literal "persist-credentials: false"
forbid_regex '^[[:space:]]*token:'
forbid_literal "916491575487"
forbid_literal "995253610162"
forbid_regex "[0-9]{12}\.dkr\.ecr\."

# --- no build, no re-signature: the artifact is copied, never recreated -----
forbid_regex "Dockerfile|docker (build|push)|buildx|build-push-action|az acr build|ko build|jib"
forbid_regex "cosign (sign|attest|attach)"

# --- the complete graph, recursively ---------------------------------------
require_literal "oras cp -r"
require_literal "crane digest"
require_literal ".sig"
require_literal ".att"
require_literal ".sbom"

# --- checksum-locked tooling from the GitOps toolchain lock ------------------
require_literal "full-profile-toolchain.lock"
require_literal "sha256sum --check --strict"
for tool in oras crane cosign; do
  require_literal "select(.name == \"${tool}\")"
done

# --- verified in ACR against the service CI identity Kyverno admits ---------
require_literal "cosign verify "
require_literal "cosign verify-attestation"
require_literal "--type spdxjson"
require_literal '^https://github\.com/MicroTodoSuite/\.github/\.github/workflows/ci\.yml@[0-9a-f]{40}$'
require_literal "--certificate-oidc-issuer https://token.actions.githubusercontent.com"
require_literal "--certificate-github-workflow-repository"
require_literal "--certificate-github-workflow-ref refs/heads/main"

# --- every `uses:` is pinned by full 40-hex SHA -----------------------------
while IFS= read -r line; do
  ref="$(sed -E 's/.*uses:[[:space:]]*//' <<<"$line" | awk '{print $1}')"
  [[ "$ref" == ./* ]] && continue
  [[ "$ref" =~ @[0-9a-f]{40}$ ]] || fail "unpinned action: $ref"
done < <(grep -E '^\s*(-\s*)?uses:' "$workflow")

sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

digest="sha256:$(printf 'a%.0s' {1..64})"
other="sha256:$(printf 'b%.0s' {1..64})"
ecr_repo="000000000000.dkr.ecr.us-east-1.amazonaws.com/lex-mts-shd-ecr-authapi"

# --- behavior: only a production-validated digest may advance ---------------
guard="$(step_script "$workflow" "Require a production-validated digest")"
[[ -n "$guard" ]] || fail "could not read the production-validation guard"
overlay="$sandbox/gitops/apps/auth-api/profiles/full/overlays/prod"
mkdir -p "$overlay"
printf 'images:\n  - name: auth-api\n    newName: %s\n    digest: %s\n' "$ecr_repo" "$digest" > "$overlay/kustomization.yaml"

guard_run() {
  env "$@" GITOPS_DIR="$sandbox/gitops" bash -c "$guard" >/dev/null 2>&1
}
guard_run SERVICE_NAME=auth-api "IMAGE_DIGEST=$digest" "IMAGE_REF=$ecr_repo@$digest" \
  || fail "the guard must accept the digest the production overlay declares"
guard_run SERVICE_NAME=auth-api "IMAGE_DIGEST=$other" "IMAGE_REF=$ecr_repo@$other" \
  && fail "the guard must reject a digest production has not validated" || true
guard_run SERVICE_NAME=auth-api "IMAGE_DIGEST=$digest" "IMAGE_REF=docker.io/someone/auth-api@$digest" \
  && fail "the guard must reject the right digest from another repository" || true
guard_run SERVICE_NAME=todos-api "IMAGE_DIGEST=$digest" "IMAGE_REF=$ecr_repo@$digest" \
  && fail "the guard must reject a service with no production overlay" || true
guard_run "SERVICE_NAME=../auth-api" "IMAGE_DIGEST=$digest" "IMAGE_REF=$ecr_repo@$digest" \
  && fail "the guard must reject a service outside the five" || true

# --- behavior: copy the complete graph and prove digest equality ------------
copy="$(step_script "$workflow" "Copy the signed service graph to ACR without rebuilding")"
[[ -n "$copy" ]] || fail "could not read the copy step"
mkdir -p "$sandbox/bin"
cat > "$sandbox/bin/crane" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
echo "crane $*" >> "$SANDBOX/calls"
[[ "$1" == digest ]] || { echo "mock crane: only digest is expected, got $1" >&2; exit 3; }
ref="$2"; hex="${IMAGE_DIGEST#sha256:}"
case "$ref" in
  "$ECR_REPO@$IMAGE_DIGEST") echo "$IMAGE_DIGEST" ;;
  "$ECR_REPO:sha256-$hex.sig"|"$ECR_REPO:sha256-$hex.att") echo "sha256:$(printf 'c%.0s' {1..64})" ;;
  "$ECR_REPO:sha256-$hex.sbom") echo "MANIFEST_UNKNOWN" >&2; exit 1 ;;
  "$ACR_LOGIN_SERVER/microtodosuite/auth-api:prod-$hex") echo "${MOCK_ACR_DIGEST:-$IMAGE_DIGEST}" ;;
  *) echo "mock crane: unexpected reference $ref" >&2; exit 3 ;;
esac
MOCK
cat > "$sandbox/bin/oras" <<'MOCK'
#!/usr/bin/env bash
echo "oras $*" >> "$SANDBOX/calls"
MOCK
chmod +x "$sandbox/bin/crane" "$sandbox/bin/oras"

copy_run() {
  : > "$sandbox/calls"; : > "$sandbox/output"
  env "$@" PATH="$sandbox/bin:$PATH" SANDBOX="$sandbox" ECR_REPO="$ecr_repo" \
    SERVICE_NAME=auth-api "IMAGE_DIGEST=$digest" "SOURCE_REF=$ecr_repo@$digest" \
    ACR_LOGIN_SERVER=mtsdrtest.azurecr.io GITHUB_OUTPUT="$sandbox/output" \
    bash -c "$copy" >/dev/null 2>"$sandbox/stderr"
}
hex="${digest#sha256:}"
acr_repo="mtsdrtest.azurecr.io/microtodosuite/auth-api"
copy_run || { cat "$sandbox/stderr" >&2; fail "the copy step failed against an equal-digest mock"; }
grep -Fxq "oras cp -r $ecr_repo@$digest $acr_repo:prod-$hex" "$sandbox/calls" \
  || fail "the artifact and its referrers must be copied recursively by digest"
grep -Fxq "oras cp -r $ecr_repo:sha256-$hex.sig $acr_repo:sha256-$hex.sig" "$sandbox/calls" \
  || fail "a tag-scheme signature must be copied with the artifact"
grep -Fxq "oras cp -r $ecr_repo:sha256-$hex.att $acr_repo:sha256-$hex.att" "$sandbox/calls" \
  || fail "a tag-scheme SBOM attestation must be copied with the artifact"
grep -Fq "sha256-$hex.sbom $acr_repo" "$sandbox/calls" \
  && fail "an absent tag-scheme artifact must be skipped, not invented" || true
[[ "$(cat "$sandbox/output")" == "acr-ref=$acr_repo@$digest" ]] \
  || fail "the step must output the ACR reference by the same digest, got: $(cat "$sandbox/output")"
if copy_run "MOCK_ACR_DIGEST=$other"; then
  fail "a different ACR manifest digest must fail the mirror"
fi
[[ -s "$sandbox/output" ]] && fail "a digest mismatch must output no ACR reference" || true

# --- promote.yml: the DR tuple and the production-validated mirror ----------
[[ -f "$promote" ]] || fail "promote.yml is missing"
grep -Fq "uses: ./.github/workflows/mirror-to-acr.yml" "$promote" \
  || fail "promote.yml must call the service mirror as a local reusable workflow"
mirror_job="$(awk '/^  mirror-to-acr:/ { f = 1; next } f && /^  [a-z]/ { exit } f' "$promote")"
grep -Fq "needs: validate" <<<"$mirror_job" || fail "promote.yml must mirror only after the tuple validation"
grep -Fq "inputs.destination == 'aks-dr'" <<<"$mirror_job" \
  || fail "promote.yml must mirror only for the aks-dr destination"
pr_job="$(awk '/^  open-promotion-pr:/ { f = 1; next } f && /^  [a-z]/ { exit } f' "$promote")"
grep -Fq "inputs.destination != 'aks-dr'" <<<"$pr_job" \
  || fail "aks-dr shares the production overlay, so promote.yml must not open a second digest PR for it"

tuple="$(step_script "$promote" "Validate digest, profile, destination and strategy")"
[[ -n "$tuple" ]] || fail "could not read promote.yml's tuple validation"
tuple_run() {
  env "$@" "IMAGE_DIGEST=$digest" bash -c "$tuple" >/dev/null 2>&1
}
tuple_run ENVIRONMENT=prod PROFILE=full DESTINATION=aks-dr STRATEGY=dr-rolling \
  || fail "promote.yml must accept prod/full/aks-dr/dr-rolling"
tuple_run ENVIRONMENT=prod PROFILE=full DESTINATION=aks-dr STRATEGY=canary \
  && fail "promote.yml must not repeat the canary on aks-dr" || true
tuple_run ENVIRONMENT=prod PROFILE=full DESTINATION=aks-dr STRATEGY=rolling \
  && fail "promote.yml must require dr-rolling on aks-dr" || true
tuple_run ENVIRONMENT=staging PROFILE=full DESTINATION=aks-dr STRATEGY=dr-rolling \
  && fail "promote.yml must accept aks-dr only for prod" || true
tuple_run ENVIRONMENT=prod PROFILE=full DESTINATION=eks-full-prod STRATEGY=dr-rolling \
  && fail "promote.yml must confine dr-rolling to aks-dr" || true
tuple_run ENVIRONMENT=prod PROFILE=economical DESTINATION=aks-dr STRATEGY=dr-rolling \
  && fail "promote.yml must accept aks-dr only for the full profile" || true
tuple_run ENVIRONMENT=prod PROFILE=full DESTINATION=eks-full-prod STRATEGY=canary \
  || fail "promote.yml must still accept the full production canary"
tuple_run ENVIRONMENT=dev PROFILE=economical DESTINATION=eks-dev STRATEGY=rolling \
  || fail "promote.yml must still accept the economical default"
env ENVIRONMENT=prod PROFILE=full DESTINATION=aks-dr STRATEGY=dr-rolling IMAGE_DIGEST=latest \
  bash -c "$tuple" >/dev/null 2>&1 && fail "promote.yml must still reject a non-digest" || true

# --- the self-test runs this contract on every change that could break it ---
for path in \
  ".github/workflows/mirror-to-acr.yml" \
  ".github/workflows/mirror-to-acr-self-test.yml" \
  ".github/workflows/promote.yml" \
  "tests/workflows/mirror-to-acr.bats"; do
  grep -Fq -- "$path" "$self_test" || fail "the self-test must run on changes to $path"
done

echo "mirror-to-acr-contract: OK: production-validated input only, AWS/Azure OIDC with no stored credential, checksum-locked tooling, recursive no-rebuild graph copy with equal manifest digests, signature and SBOM attestation verified in ACR against the service CI identity, promote.yml wired for prod/full/aks-dr/dr-rolling."
