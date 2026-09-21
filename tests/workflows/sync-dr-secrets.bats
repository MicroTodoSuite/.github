#!/usr/bin/env bash
# Contract test for the disaster-recovery secret seed (gitops spec 009 T121,
# for T131). Same grep-the-contract style as tests/workflows/mirror-platform-
# images.bats, plus a behavioral half: the seed script is read out of the
# workflow and run against mock `aws` and `az` binaries, so the guarantees that
# matter most (early masking, mode-0600 files, cleanup, the exact mapping, and
# an equality boolean that never becomes a digest) are observed, not grepped.
# Executable bash, run directly; no bats framework, matching the repository's
# other contract tests.
#
# research.md Decision 14 and data-model.md SecretTransfer are the requirements:
# exactly four AWS Secrets Manager sources are written to exactly four Azure Key
# Vault names through short-lived OIDC sessions; the production JWT is copied
# unchanged and proven equal in process; value_artifacts must equal zero across
# logs, outputs, caches and artifacts.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow="$repo_root/.github/workflows/sync-dr-secrets.yml"
self_test="$repo_root/.github/workflows/sync-dr-secrets-self-test.yml"
seed_step="Seed the four approved secrets without persisting a value"

fail() { echo "sync-dr-secrets-contract: $*" >&2; exit 1; }

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

# Prints the body of a step's `run: |` block, de-indented, so it can be executed.
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

# --- reusable, and runnable by hand for a rotation --------------------------
require_literal "workflow_call"
require_literal "workflow_dispatch"

# --- OIDC only, no static credential ----------------------------------------
# The AWS role trusts repository + environment + workflow file, so the job must
# run inside a GitHub environment; the Azure identity is federated, not a secret.
require_literal "id-token: write"
require_literal "aws-actions/configure-aws-credentials@61815dcd50bd041e203e49132bacad1fd04d2708"
require_literal "microtodosuite-github-dr-secret-seed"
require_literal "azure/login@a641126d1b8aa4d1fa005f4f92df94a3a4c4c906"
require_literal "client-id:"
require_literal "tenant-id:"
require_literal "subscription-id:"
require_literal 'environment: ${{ inputs.github-environment }}'
forbid_regex "aws_access_key_id|AWS_SECRET_ACCESS_KEY|AWS_ACCESS_KEY_ID|AWS_SESSION_TOKEN"
forbid_regex "creds:|client-secret|AZURE_CLIENT_SECRET|AZURE_CREDENTIALS"
grep -Eq '^[[:space:]]*secrets:' "$workflow" \
  && fail "the seed must take no caller secret; it authenticates through OIDC alone" || true
forbid_literal "916491575487"
forbid_literal "995253610162"
forbid_regex "arn:aws:iam::[0-9]{12}:"

# --- exact four-secret mapping ---------------------------------------------
declare -A mapping=(
  ["microtodosuite/prod/auth-api-secrets"]="microtodosuite-prod-auth-api-secrets"
  ["microtodosuite/observability/alertmanager-slack-webhook"]="microtodosuite-observability-alertmanager-slack-webhook"
  ["microtodosuite/security/falcosidekick-slack-webhook"]="microtodosuite-security-falcosidekick-slack-webhook"
  ["microtodosuite/observability/grafana-admin"]="microtodosuite-observability-grafana-admin"
)
for source in "${!mapping[@]}"; do
  require_literal "\"${source}=${mapping[$source]}\""
done
mapped="$(grep -Ec '^[[:space:]]+"microtodosuite/[^"=]+=microtodosuite-[a-z0-9-]+"$' "$workflow" || true)"
[[ "$mapped" -eq 4 ]] || fail "the mapping must hold exactly four source=target pairs, found $mapped"

# --- no value persistence, no value-derived output --------------------------
forbid_literal "actions/cache"
forbid_literal "upload-artifact"
forbid_literal "GITHUB_ENV"
forbid_regex 'set -[a-z]*x'
forbid_regex 'sha(1|224|256|384|512)sum|md5sum|b2sum|cksum|shasum|openssl +dgst|hashlib'
forbid_literal "--value" # a value on a command line is visible in the process table and az logs
forbid_literal "tee "
forbid_literal "actions/checkout" # the seed needs no repository content
while IFS= read -r line; do
  [[ "$line" == *'jwt-value-match='* ]] \
    || fail "the only step output may be the jwt-value-match boolean: $line"
done < <(grep -F 'GITHUB_OUTPUT' "$workflow")
require_literal "jwt-value-match"

# --- every `uses:` is pinned by full 40-hex SHA -----------------------------
while IFS= read -r line; do
  ref="$(sed -E 's/.*uses:[[:space:]]*//' <<<"$line" | awk '{print $1}')"
  [[ "$ref" == ./* ]] && continue
  [[ "$ref" =~ @[0-9a-f]{40}$ ]] || fail "unpinned action: $ref"
done < <(grep -E '^\s*(-\s*)?uses:' "$workflow")

# --- behavior: run the seed script against mock clouds ----------------------
script="$(step_script "$workflow" "$seed_step")"
[[ -n "$script" ]] || fail "could not read the step '$seed_step' from the workflow"
grep -Eq '^set \+x' <<<"$script" || fail "the seed script must disable shell tracing explicitly"
grep -Fq 'umask 077' <<<"$script" || fail "the seed script must create files owner-only"
grep -Eq '^trap [^ ]+ EXIT' <<<"$script" || fail "the seed script must install a cleanup trap on EXIT"

sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
mkdir -p "$sandbox/bin" "$sandbox/vault" "$sandbox/runner"

# Values are deliberately awkward: multi-line, JSON with a nested secret, no
# trailing newline. The JWT carries a trailing newline to prove a byte-exact copy.
printf 'jwt-line-one\njwt-line-two-SECRET\n' > "$sandbox/src-auth"
printf 'https://hooks.example.invalid/ALERT-SECRET' > "$sandbox/src-alert"
printf 'https://hooks.example.invalid/FALCO-SECRET' > "$sandbox/src-falco"
printf '{"username":"admin","password":"GRAFANA-SECRET"}' > "$sandbox/src-grafana"

cat > "$sandbox/bin/aws" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
echo "aws $*" >> "$SANDBOX/calls"
id=""; version=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    --secret-id) id="${args[$((i + 1))]}" ;;
    --version-id) version="${args[$((i + 1))]}" ;;
  esac
done
case "$id" in
  microtodosuite/prod/auth-api-secrets) f=auth ;;
  microtodosuite/observability/alertmanager-slack-webhook) f=alert ;;
  microtodosuite/security/falcosidekick-slack-webhook) f=falco ;;
  microtodosuite/observability/grafana-admin) f=grafana ;;
  *) echo "mock aws: unapproved secret id: $id" >&2; exit 3 ;;
esac
case "$2" in
  describe-secret)
    jq -n --arg v "ver-$f" '{($v): ["AWSCURRENT"], "ver-old": ["AWSPREVIOUS"]}' ;;
  get-secret-value)
    [[ "$version" == "ver-$f" ]] || { echo "mock aws: read without the pinned AWSCURRENT version" >&2; exit 3; }
    jq -n --rawfile s "$SANDBOX/src-$f" --arg v "$version" '{SecretString: $s, VersionId: $v}' ;;
  *) echo "mock aws: unexpected call: $*" >&2; exit 3 ;;
esac
MOCK

cat > "$sandbox/bin/az" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
echo "az $*" >> "$SANDBOX/calls"
name=""; file=""; query=""; output=""; encoding=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    --name|-n) name="${args[$((i + 1))]}" ;;
    --file|-f) file="${args[$((i + 1))]}" ;;
    --query) query="${args[$((i + 1))]}" ;;
    --output|-o) output="${args[$((i + 1))]}" ;;
    --encoding|-e) encoding="${args[$((i + 1))]}" ;;
    --vault-name) [[ "${args[$((i + 1))]}" == "kv-dr-test" ]] || { echo "mock az: wrong vault" >&2; exit 3; } ;;
  esac
done
case "$3" in
  set)
    [[ -n "$file" ]] || { echo "mock az: a value must come from a file" >&2; exit 3; }
    [[ "$(stat -c %a "$file")" == 600 ]] || { echo "mock az: value file is not mode 0600" >&2; exit 3; }
    [[ "$(stat -c %a "$(dirname "$file")")" == 700 ]] || { echo "mock az: value directory is not mode 0700" >&2; exit 3; }
    [[ "$encoding" == utf-8 ]] || { echo "mock az: encoding must be utf-8" >&2; exit 3; }
    [[ "$output" == none ]] || { echo "mock az: set must print nothing (--output none)" >&2; exit 3; }
    # Early masking: every line of the value is already masked when it reaches az.
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" ]] && continue
      grep -Fxq -- "::add-mask::$line" "$SANDBOX/stdout" \
        || { echo "mock az: a value line reached az before it was masked" >&2; exit 3; }
    done < "$file"
    echo "$file" >> "$SANDBOX/value-files"
    cp "$file" "$SANDBOX/vault/$name"
    [[ -n "${MOCK_AZ_FAIL_SET:-}" ]] && { echo "mock az: injected failure" >&2; exit 4; }
    exit 0 ;;
  show)
    case "$query" in
      id) echo "https://kv-dr-test.vault.azure.net/secrets/$name/kvver0001" ;;
      value)
        [[ "$output" == json ]] || { echo "mock az: read the value back as JSON" >&2; exit 3; }
        if [[ -n "${MOCK_AZ_DIVERGE:-}" ]]; then jq -n '"a-different-value"'; else jq -n --rawfile s "$SANDBOX/vault/$name" '$s'; fi ;;
      *) echo "mock az: unexpected query: $query" >&2; exit 3 ;;
    esac ;;
  *) echo "mock az: unexpected call: $*" >&2; exit 3 ;;
esac
MOCK
chmod +x "$sandbox/bin/aws" "$sandbox/bin/az"

run_seed() {  # extra env assignments...
  : > "$sandbox/stdout"; : > "$sandbox/calls"; : > "$sandbox/value-files"
  : > "$sandbox/output"; : > "$sandbox/summary"; rm -rf "$sandbox/vault"/* "$sandbox/runner"/*
  # `bash -x` proves the script's own `set +x` wins over an inherited trace.
  env "$@" PATH="$sandbox/bin:$PATH" SANDBOX="$sandbox" \
    RUNNER_TEMP="$sandbox/runner" GITHUB_OUTPUT="$sandbox/output" \
    GITHUB_STEP_SUMMARY="$sandbox/summary" KEY_VAULT_NAME=kv-dr-test \
    bash -x -c "$script" >> "$sandbox/stdout" 2> "$sandbox/stderr"
}

leaks() {  # a value line anywhere but on an add-mask command is a leak
  local f line
  for f in "$sandbox/stdout" "$sandbox/stderr" "$sandbox/output" "$sandbox/summary"; do
    for line in jwt-line-one jwt-line-two-SECRET ALERT-SECRET FALCO-SECRET GRAFANA-SECRET; do
      if grep -F -- "$line" "$f" | grep -vqF '::add-mask::'; then
        fail "value material '$line' leaked into $(basename "$f")"
      fi
    done
  done
}

run_seed || { cat "$sandbox/stderr" >&2; fail "the seed script failed against a consistent mock"; }
leaks
for source in "${!mapping[@]}"; do
  target="${mapping[$source]}"
  case "$source" in
    */auth-api-secrets) f=auth ;; */alertmanager-slack-webhook) f=alert ;;
    */falcosidekick-slack-webhook) f=falco ;; */grafana-admin) f=grafana ;;
  esac
  [[ -f "$sandbox/vault/$target" ]] || fail "$source was not written to $target"
  cmp -s "$sandbox/src-$f" "$sandbox/vault/$target" || fail "$target does not hold the exact bytes of $source"
done
[[ "$(find "$sandbox/vault" -type f | wc -l)" -eq 4 ]] || fail "the seed wrote a Key Vault name outside the four approved ones"
[[ "$(grep -c '^aws secretsmanager get-secret-value' "$sandbox/calls")" -eq 4 ]] \
  || fail "the seed must read exactly four source values"
grep -Fxq '::add-mask::GRAFANA-SECRET' "$sandbox/stdout" \
  || fail "a JSON value must have each string field masked, not only its whole line"
[[ "$(cat "$sandbox/output")" == "jwt-value-match=true" ]] \
  || fail "the step output must be exactly jwt-value-match=true, got: $(cat "$sandbox/output")"
while IFS= read -r f; do
  [[ ! -e "$f" ]] || fail "a value file survived the run: $f"
done < "$sandbox/value-files"
[[ -z "$(find "$sandbox/runner" -mindepth 1 -print -quit)" ]] || fail "the seed left files in RUNNER_TEMP"
grep -Fq 'ver-auth' "$sandbox/summary" || fail "the evidence must record the non-secret source version"
grep -Fq 'kvver0001' "$sandbox/summary" || fail "the evidence must record the non-secret target version"

# A JWT that reads back different is a blocked transfer, and says false.
if run_seed MOCK_AZ_DIVERGE=1; then fail "a diverging JWT read-back must fail the seed"; fi
leaks
[[ "$(cat "$sandbox/output")" == "jwt-value-match=false" ]] \
  || fail "a diverging JWT must report jwt-value-match=false"

# A failure halfway still removes every value file: the trap, not the happy path, cleans up.
if run_seed MOCK_AZ_FAIL_SET=1; then fail "a failed Key Vault write must fail the seed"; fi
leaks
while IFS= read -r f; do
  [[ ! -e "$f" ]] || fail "a value file survived a failed run: $f"
done < "$sandbox/value-files"
[[ -z "$(find "$sandbox/runner" -mindepth 1 -print -quit)" ]] || fail "a failed run left files in RUNNER_TEMP"

# --- promote.yml seeds only after the production-validated DR mirror --------
promote="$repo_root/.github/workflows/promote.yml"
grep -Fq "uses: ./.github/workflows/sync-dr-secrets.yml" "$promote" \
  || fail "promote.yml must call the seed as a local reusable workflow"
awk '/^  sync-dr-secrets:/ { f = 1; next } f && /^  [a-z]/ { exit } f' "$promote" | grep -Fq "needs: mirror-to-acr" \
  || fail "promote.yml must seed only after the production-validated service mirror"

# --- the self-test runs this contract on every change that could break it ---
for path in \
  ".github/workflows/sync-dr-secrets.yml" \
  ".github/workflows/sync-dr-secrets-self-test.yml" \
  "tests/workflows/sync-dr-secrets.bats"; do
  grep -Fq -- "$path" "$self_test" || fail "the self-test must run on changes to $path"
done

echo "sync-dr-secrets-contract: OK: OIDC-only AWS/Azure sessions in a GitHub environment, exactly four mapped secrets copied byte-exact, early masking, tracing disabled, mode-0600 files removed by an EXIT trap, no cache/artifact/env/value output, an in-process JWT equality boolean with no digest, SHA-pinned actions."
