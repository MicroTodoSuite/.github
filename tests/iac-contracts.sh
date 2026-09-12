#!/usr/bin/env bash
# Contract tests for scripts/iac/contracts.py.
#
# Every rule is verified by mutation: a valid fixture passes, and one targeted
# change to a fresh copy of it makes the expected rule fail. A rule whose
# mutation does not fail is a rule that is not enforced.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
contracts="$repo_root/scripts/iac/contracts.py"
fixtures="$repo_root/tests/fixtures/iac"
python="${IAC_CONTRACTS_PYTHON:-python3}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

run_contracts() {
  "$python" "$contracts" "$@"
}

report_pass() { printf 'ok   %s\n' "$1"; }
report_fail() {
  printf 'FAIL %s\n' "$1"
  failures=$((failures + 1))
}

# expect_clean NAME ARGS... — the contracts exit 0 and report no failure.
expect_clean() {
  local name="$1" output
  shift
  if output="$(run_contracts "$@" 2>&1)"; then
    report_pass "$name"
  else
    report_fail "$name (expected no finding)"
    printf '%s\n' "$output" | sed 's/^/     /'
  fi
}

# expect_rule NAME RULE ARGS... — the contracts exit 1 and report RULE.
expect_rule() {
  local name="$1" rule="$2" output status=0
  shift 2
  output="$(run_contracts "$@" 2>&1)" || status=$?
  if [ "$status" -eq 0 ]; then
    report_fail "$name (exited 0, expected $rule)"
  elif [ "$status" -ne 1 ]; then
    report_fail "$name (exited $status, expected 1 with $rule)"
    printf '%s\n' "$output" | sed 's/^/     /'
  elif grep -q "^FAIL $rule " <<<"$output"; then
    report_pass "$name"
  else
    report_fail "$name (expected $rule)"
    printf '%s\n' "$output" | sed 's/^/     /'
  fi
}

fresh_module() {
  rm -rf "$work/queue"
  cp -R "$fixtures/modules/queue" "$work/queue"
  printf '%s\n' "$work/queue"
}

fresh_live() {
  rm -rf "$work/live"
  cp -R "$fixtures/live" "$work/live"
  printf '%s\n' "$work/live"
}

fresh_plan() {
  cp "$fixtures/plans/workload.json" "$work/plan.json"
  printf '%s\n' "$work/plan.json"
}

# mutate_json FILE PYTHON-EXPRESSION — edits the parsed document `d` in place.
mutate_json() {
  "$python" - "$1" "$2" <<'PY'
import json, sys
path, expression = sys.argv[1], sys.argv[2]
with open(path) as handle:
    d = json.load(handle)
exec(expression)
with open(path, "w") as handle:
    json.dump(d, handle)
PY
}

root_rel="aws/environments/fdev/workload"

echo "== valid fixtures"
expect_clean "module fixture passes" module "$fixtures/modules/queue"
expect_clean "live fixture passes" repo "$fixtures/live" --kind live
expect_clean "modules repository fixture passes" repo "$fixtures/modules" --kind modules
expect_clean "plan fixture passes" plan "$fixtures/plans/workload.json" --client lex --project mts --domain workload

echo "== PC-IAC-001 module structure"
m="$(fresh_module)"; rm "$m/data.tf"
expect_rule "a missing data.tf fails" PC-IAC-001 module "$m"
m="$(fresh_module)"; printf '# Extra file.\n' >"$m/extra.tf"
expect_rule "an extra top-level .tf file fails" PC-IAC-001 module "$m"
m="$(fresh_module)"; rm "$m/sample/locals.tf"
expect_rule "a missing sample file fails" PC-IAC-001 module "$m"
m="$(fresh_module)"; rm "$m/CHANGELOG.md"
expect_rule "a missing CHANGELOG.md fails" PC-IAC-001 module "$m"
m="$(fresh_module)"; : >"$m/locals.tf"
expect_rule "an empty file without a descriptive comment fails" PC-IAC-001 module "$m"

echo "== PC-IAC-002 variables"
m="$(fresh_module)"; sed -i '/description = "Name of the queue/d' "$m/variables.tf"
expect_rule "a variable without a description fails" PC-IAC-002 module "$m"
m="$(fresh_module)"; cat >>"$m/variables.tf" <<'HCL'

variable "retention_label" {
  type        = string
  description = "A string input without validation."
}
HCL
expect_rule "a string variable without validation fails" PC-IAC-002 module "$m"
m="$(fresh_module)"; cat >>"$m/variables.tf" <<'HCL'

variable "fifo" {
  type        = bool
  description = "A boolean input needs no validation block."
  default     = false
}
HCL
expect_clean "a boolean variable without validation passes" module "$m"
m="$(fresh_module)"; "$python" - "$m/variables.tf" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
text = re.sub(r'variable "environment" \{.*?\n\}\n', '', text, flags=re.S)
open(path, "w").write(text)
PY
sed -i 's/var.environment/"fdev"/' "$m/locals.tf"
expect_rule "a missing governance variable fails" PC-IAC-002 module "$m"
m="$(fresh_module)"; sed -i '/^variable "queue" {/,/^}/ s/  type = object({/  default = null\n  type = object({/' "$m/variables.tf"
expect_rule "a sizing object with a default fails" PC-IAC-002 module "$m"

echo "== PC-IAC-003 identifiers"
m="$(fresh_module)"; sed -i 's/"aws_sqs_queue" "this"/"aws_sqs_queue" "MainQueue"/; s/aws_sqs_queue\.this/aws_sqs_queue.MainQueue/g' "$m/main.tf" "$m/outputs.tf"
expect_rule "a non-snake-case identifier fails" PC-IAC-003 module "$m"
m="$(fresh_module)"; sed -i 's/"aws_sqs_queue" "this"/"aws_sqs_queue" "main"/; s/aws_sqs_queue\.this/aws_sqs_queue.main/g' "$m/main.tf" "$m/outputs.tf"
expect_rule "a principal resource not named this fails" PC-IAC-003 module "$m"

echo "== PC-IAC-004 tags"
m="$(fresh_module)"; "$python" - "$m/variables.tf" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
text = re.sub(r'variable "additional_tags" \{.*?\n\}\n', '', text, flags=re.S)
open(path, "w").write(text)
PY
sed -i 's/, var.additional_tags//' "$m/locals.tf"
expect_rule "a module without additional_tags fails" PC-IAC-004 module "$m"
l="$(fresh_live)"; "$python" - "$l/$root_rel/providers.tf" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
text = re.sub(r'\n  default_tags \{.*?\n  \}\n', '\n', text, flags=re.S)
open(path, "w").write(text)
PY
expect_rule "a root provider without default_tags fails" PC-IAC-004 repo "$l" --kind live
p="$(fresh_plan)"; mutate_json "$p" 'del d["resource_changes"][0]["change"]["after"]["tags_all"]["CostCenter"]'
expect_rule "a planned resource missing a transversal tag fails" PC-IAC-004 plan "$p" --client lex --project mts
p="$(fresh_plan)"; mutate_json "$p" 'd["resource_changes"][0]["change"]["after"]["tags"]["Name"] = "lex-mts-fdev-sqs-other"; d["resource_changes"][0]["change"]["after"]["tags_all"]["Name"] = "lex-mts-fdev-sqs-other"'
expect_rule "a Name tag that differs from the name fails" PC-IAC-004 plan "$p" --client lex --project mts
p="$(fresh_plan)"; mutate_json "$p" 'd["resource_changes"][0]["change"]["after"]["tags_all"]["Environment"] = "fprd"'
expect_rule "an Environment tag that contradicts the name fails" PC-IAC-004 plan "$p" --client lex --project mts

echo "== PC-IAC-003 physical names (plan)"
p="$(fresh_plan)"; mutate_json "$p" 'a = d["resource_changes"][0]["change"]["after"]; a["name"] = a["tags"]["Name"] = a["tags_all"]["Name"] = "lex-mts-fdev-sqs-notifications1"'
expect_rule "a name longer than 28 characters fails" PC-IAC-003 plan "$p" --client lex --project mts
p="$(fresh_plan)"; mutate_json "$p" 'a = d["resource_changes"][0]["change"]["after"]; a["name"] = a["tags"]["Name"] = a["tags_all"]["Name"] = "lex-mts-fdev-sg-events"'
expect_rule "a type segment that does not match the resource fails" PC-IAC-003 plan "$p" --client lex --project mts
p="$(fresh_plan)"; mutate_json "$p" 'a = d["resource_changes"][0]["change"]["after"]; a["name"] = a["tags"]["Name"] = a["tags_all"]["Name"] = "gcs-mts-fdev-sqs-events"'
expect_rule "a name with another client code fails" PC-IAC-003 plan "$p" --client lex --project mts
p="$(fresh_plan)"; mutate_json "$p" 'a = d["resource_changes"][0]["change"]["after"]; a["name"] = None; a["name_prefix"] = "lex-mts-fdev-sqs-"'
expect_rule "a generated name_prefix fails" PC-IAC-003 plan "$p" --client lex --project mts
p="$(fresh_plan)"; mutate_json "$p" 'd["resource_changes"][2]["change"]["after"]["bucket"] = "lex-mts-shd-s3-tfstate-1a2b3c"'
expect_rule "a state bucket without the account suffix fails" PC-IAC-003 plan "$p" --client lex --project mts
p="$(fresh_plan)"; mutate_json "$p" 'd["resource_changes"][0]["change"]["actions"] = ["delete"]; d["resource_changes"][0]["change"]["after"] = None'
expect_clean "a resource being deleted is not named" plan "$p" --client lex --project mts

echo "== PC-IAC-005 providers"
m="$(fresh_module)"; printf '\nprovider "aws" {\n  region = "us-east-1"\n}\n' >>"$m/providers.tf"
expect_rule "a provider block inside a module fails" PC-IAC-005 module "$m"
m="$(fresh_module)"; sed -i '/provider = aws.project/d' "$m/main.tf"
expect_rule "a module resource without aws.project fails" PC-IAC-005 module "$m"
m="$(fresh_module)"; sed -i '/configuration_aliases/d' "$m/versions.tf"
expect_rule "a module without configuration_aliases fails" PC-IAC-005 module "$m"
l="$(fresh_live)"; sed -i '/alias *= "principal"/d' "$l/$root_rel/providers.tf"
expect_rule "a root provider without the principal alias fails" PC-IAC-005 repo "$l" --kind live
l="$(fresh_live)"; "$python" - "$l/$root_rel/providers.tf" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
text = re.sub(r'\n  dynamic "assume_role" \{.*?\n  \}\n', '\n', text, flags=re.S)
open(path, "w").write(text)
PY
expect_rule "a root provider without assume_role fails" PC-IAC-005 repo "$l" --kind live

echo "== PC-IAC-006 versions"
m="$(fresh_module)"; sed -i 's/required_version = ">= 1.11.0"/required_version = "= 1.15.8"/' "$m/versions.tf"
expect_rule "an exact required_version fails" PC-IAC-006 module "$m"
m="$(fresh_module)"; sed -i 's/version               = ">= 6.0.0"/version               = "= 6.64.0"/' "$m/versions.tf"
expect_rule "an exact provider pin inside a module fails" PC-IAC-006 module "$m"
m="$(fresh_module)"; printf '# lock\n' >"$m/.terraform.lock.hcl"
expect_rule "a module lock file fails" PC-IAC-006 module "$m"
l="$(fresh_live)"; rm "$l/$root_rel/.terraform.lock.hcl"
expect_rule "a root without a lock file fails" PC-IAC-006 repo "$l" --kind live
l="$(fresh_live)"; sed -i 's/version = "= 6.64.0"/version = ">= 6.0.0"/' "$l/$root_rel/versions.tf"
expect_rule "a root with an open provider range fails" PC-IAC-006 repo "$l" --kind live

echo "== PC-IAC-007 outputs"
m="$(fresh_module)"; sed -i '/description = "ARN of the queue."/d' "$m/outputs.tf"
expect_rule "an output without a description fails" PC-IAC-007 module "$m"
m="$(fresh_module)"; printf '\noutput "queue" {\n  description = "The whole queue."\n  value       = aws_sqs_queue.this\n}\n' >>"$m/outputs.tf"
expect_rule "an output returning a whole resource fails" PC-IAC-007 module "$m"
m="$(fresh_module)"; printf '\noutput "queue_retention" {\n  description = "Retention period."\n  value       = aws_sqs_queue.this.message_retention_seconds\n}\n' >>"$m/outputs.tf"
expect_rule "an output name without a recognised suffix fails" PC-IAC-007 module "$m"

echo "== PC-IAC-008 state backend"
m="$(fresh_module)"; sed -i 's/^terraform {/terraform {\n  backend "s3" {}\n/' "$m/versions.tf"
expect_rule "a backend inside a module fails" PC-IAC-008 module "$m"
l="$(fresh_live)"; sed -i 's/backend "s3" {}/backend "s3" {\n    bucket = "lex-mts-shd-s3-tfstate"\n  }/' "$l/$root_rel/versions.tf"
expect_rule "a root backend with values fails" PC-IAC-008 repo "$l" --kind live
l="$(fresh_live)"; sed -i '/backend "s3" {}/d' "$l/$root_rel/versions.tf"
expect_rule "a root without a backend fails" PC-IAC-008 repo "$l" --kind live

echo "== PC-IAC-010 protected resources"
m="$(fresh_module)"; cat >>"$m/main.tf" <<'HCL'

resource "aws_ecr_repository" "images" {
  provider = aws.project

  name = var.queue.name
  tags = local.tags
}
HCL
expect_rule "an ECR repository without prevent_destroy fails" PC-IAC-010 module "$m"

echo "== PC-IAC-011 data sources in modules"
m="$(fresh_module)"; printf '\ndata "aws_vpc" "selected" {\n  provider = aws.project\n  id       = "vpc-0123456789abcdef0"\n}\n' >>"$m/data.tf"
expect_rule "a lookup data source inside a module fails" PC-IAC-011 module "$m"
m="$(fresh_module)"; printf '\ndata "aws_partition" "current" {\n  provider = aws.project\n}\n' >>"$m/data.tf"
expect_clean "an allowed computational data source passes" module "$m"

echo "== PC-IAC-012 locals"
m="$(fresh_module)"; printf '\nlocals {\n  extra = 1\n}\n' >>"$m/locals.tf"
expect_rule "two locals blocks in locals.tf fail" PC-IAC-012 module "$m"
m="$(fresh_module)"; printf '\nlocals {\n  extra = 1\n}\n' >>"$m/main.tf"
expect_rule "a locals block outside locals.tf fails" PC-IAC-012 module "$m"
l="$(fresh_live)"; sed -i 's/governance_prefix/name_prefix_value/g' "$l/$root_rel/locals.tf"
expect_rule "a root without governance_prefix fails" PC-IAC-012 repo "$l" --kind live

echo "== PC-IAC-015 module sources"
l="$(fresh_live)"; sed -i 's|source = "git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//queue?ref=queue-v1.0.0"|source = "../../../modules/queue"|' "$l/$root_rel/main.tf"
expect_rule "a local module source fails" PC-IAC-015 repo "$l" --kind live
l="$(fresh_live)"; sed -i 's|?ref=queue-v1.0.0|?ref=main|' "$l/$root_rel/main.tf"
expect_rule "a branch reference fails" PC-IAC-015 repo "$l" --kind live
l="$(fresh_live)"; sed -i 's|?ref=queue-v1.0.0||' "$l/$root_rel/main.tf"
expect_rule "an unpinned Git source fails" PC-IAC-015 repo "$l" --kind live
l="$(fresh_live)"; sed -i 's|?ref=queue-v1.0.0|?ref=network-v1.0.0|' "$l/$root_rel/main.tf"
expect_rule "a tag of another module fails" PC-IAC-015 repo "$l" --kind live

echo "== PC-IAC-016 secrets"
m="$(fresh_module)"; cat >>"$m/variables.tf" <<'HCL'

variable "alert_webhook_url" {
  type        = string
  description = "Webhook that receives alerts."

  validation {
    condition     = startswith(var.alert_webhook_url, "https://")
    error_message = "The webhook must be an HTTPS URL."
  }
}
HCL
expect_rule "a secret-named variable without sensitive fails" PC-IAC-016 module "$m"

echo "== PC-IAC-017 remote state and exceptions"
l="$(fresh_live)"; cat >>"$l/$root_rel/data.tf" <<'HCL'

data "terraform_remote_state" "network" {
  backend = "s3"
  config  = {}
}
HCL
expect_rule "an unrecorded terraform_remote_state fails" PC-IAC-017 repo "$l" --kind live
cat >"$l/docs/iac-exceptions.md" <<'MD'
# Infrastructure-as-Code Exceptions

| Rule | Path | Resource | Reason | Expiry |
| --- | --- | --- | --- | --- |
| PC-IAC-017 | aws/environments/fdev/workload | data.terraform_remote_state.network | Test fixture | When the network outputs move to tags |
MD
expect_clean "a recorded exception with an expiry waives the finding" repo "$l" --kind live
sed -i 's/| When the network outputs move to tags |/|  |/' "$l/docs/iac-exceptions.md"
expect_rule "an exception without an expiry does not waive" PC-IAC-017 repo "$l" --kind live

echo "== PC-IAC-022 domain separation"
l="$(fresh_live)"; printf '\nresource "aws_vpc" "extra" {\n  provider   = aws.principal\n  cidr_block = local.vpc_cidr\n}\n' >>"$l/$root_rel/main.tf"
expect_rule "a networking resource in a workload root fails" PC-IAC-022 repo "$l" --kind live
p="$(fresh_plan)"
expect_rule "a planned resource outside the root's domain fails" PC-IAC-022 plan "$p" --client lex --project mts --domain networking

echo "== PC-IAC-023 single responsibility"
m="$(fresh_module)"; cat >>"$m/main.tf" <<'HCL'

resource "aws_iam_role" "consumer" {
  provider = aws.project

  name               = var.queue.name
  assume_role_policy = "{}"
  tags               = local.tags
}
HCL
expect_rule "an IAM role inside a service module fails" PC-IAC-023 module "$m"
printf '{"module_owners": {"queue": ["aws_iam_role"]}}\n' >"$work/owners.json"
expect_clean "a declared owner may create the type" module "$m" --config "$work/owners.json"

echo "== PC-IAC-025 names built in the root"
# shellcheck disable=SC2016 # the HCL interpolation is written literally on purpose
m="$(fresh_module)"; sed -i 's/  name = var.queue.name/  name = "${var.client}-${var.project}-${var.environment}-sqs-main"/' "$m/main.tf"
expect_rule "a module assembling a name from governance variables fails" PC-IAC-025 module "$m"

echo "== PC-IAC-026 sample"
m="$(fresh_module)"; printf '\nresource "aws_sqs_queue" "extra" {}\n' >>"$m/sample/main.tf"
expect_rule "a resource in sample/main.tf fails" PC-IAC-026 module "$m"
m="$(fresh_module)"; sed -i 's|source = "../"|source = "git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//queue?ref=queue-v1.0.0"|' "$m/sample/main.tf"
expect_rule "a sample that does not call ../ fails" PC-IAC-026 module "$m"

echo "== PC-IAC-018 tests"
m="$(fresh_module)"; rm "$m"/tests/*.tftest.hcl
expect_rule "a module without terraform test files fails" PC-IAC-018 module "$m"

echo "== MTS-IAC-102 live repositories hold no modules"
l="$(fresh_live)"; mkdir -p "$l/aws/modules/queue"; printf '# copy\n' >"$l/aws/modules/queue/main.tf"
expect_rule "a module copy in a live repository fails" MTS-IAC-102 repo "$l" --kind live

echo "== MTS-IAC-103 account and region parameters"
l="$(fresh_live)"; sed -i 's/region              = var.region/region              = "us-east-1"/' "$l/$root_rel/providers.tf"
expect_rule "a literal region in a root provider fails" MTS-IAC-103 repo "$l" --kind live
l="$(fresh_live)"; sed -i 's/allowed_account_ids = \[var.aws_account_id\]/allowed_account_ids = ["575172595729"]/' "$l/$root_rel/providers.tf"
expect_rule "a literal account in a root fails" MTS-IAC-103 repo "$l" --kind live
l="$(fresh_live)"; sed -i '/allowed_account_ids/d' "$l/$root_rel/providers.tf"
expect_rule "a root provider without allowed_account_ids fails" MTS-IAC-103 repo "$l" --kind live

echo "== output format"
output="$(run_contracts --format json module "$(fresh_module)" 2>&1 || true)"
if "$python" -c 'import json, sys; d = json.loads(sys.argv[1]); assert d["findings"] == [] and d["checked"] >= 1' "$output"; then
  report_pass "json output of a clean module"
else
  report_fail "json output of a clean module"
  printf '%s\n' "$output" | sed 's/^/     /'
fi

echo
if [ "$failures" -ne 0 ]; then
  echo "iac-contracts: $failures case(s) failed" >&2
  exit 1
fi
echo "iac-contracts: every case passed"
