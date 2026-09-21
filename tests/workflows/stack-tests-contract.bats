#!/usr/bin/env bash
# Contract test for the reusable stack-tests workflow (gitops spec 007 T027).
# Same grep-the-contract style as tests/workflows/reusable-workflow-contract.bats.
# stack-command is required: true with no default, exactly like ci.yml's
# test-command was before gitops spec 003 T024 found it could be silently
# satisfied by an empty string -- this guards the same failure mode here.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
stack_tests="$root/.github/workflows/stack-tests.yml"

fail() { echo "stack-tests-contract: $*" >&2; exit 1; }
have() { grep -Fq -- "$2" "$1" || fail "$3"; }

[[ -f "$stack_tests" ]] || fail "missing required file: $stack_tests"

have "$stack_tests" "workflow_call" "stack-tests.yml must be a reusable workflow"
have "$stack_tests" "stack-command:" "stack-tests.yml must take a required stack-command gate"
have "$stack_tests" "stack-command must not be empty or blank" \
  "stack-tests.yml must fail visibly on an empty stack-command, never pass having run no gate (FR-017, gitops spec 007 T027)"

echo "stack-tests-contract: OK -- stack-tests.yml is a reusable workflow that fails visibly on an empty stack-command."
