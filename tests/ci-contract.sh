#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="$repo_root/.github/workflows/ci.yml"

fail() {
  echo "ci-contract: $*" >&2
  exit 1
}

require_literal() {
  local literal="$1"
  grep -Fq -- "$literal" "$workflow" || fail "missing required workflow contract: $literal"
}

line_of() {
  local literal="$1"
  grep -Fnm1 -- "$literal" "$workflow" | cut -d: -f1
}

require_literal "test-command:"
require_literal "source-audit-command:"
require_literal "ecr-repository:"
require_literal "publisher-role-arn:"
require_literal "Run repository tests"
require_literal "Build image once locally"
require_literal "Scan the exact local image"
require_literal "Generate the exact local image SBOM"
require_literal "Push the already-tested image once"
require_literal "Resolve the immutable ECR digest"
require_literal "Attach SBOM and keylessly sign the immutable digest"
require_literal "github.event_name == 'push'"
require_literal "github.ref == 'refs/heads/main'"
require_literal "github.repository_owner == 'MicroTodoSuite'"
require_literal "microtodosuite-github-ecr-publisher"
require_literal "995253610162.dkr.ecr."
require_literal "amazonaws.com/microtodosuite/"

grep -Eq '^[[:space:]]+uses: [^#]+@[0-9a-f]{40}([[:space:]]+#.*)?$' "$workflow" \
  || fail "workflow does not contain immutable action references"
if grep -Eq '^[[:space:]]+uses: [^#]+@(v[0-9]+|main|master)([[:space:]]+#.*)?$' "$workflow"; then
  fail "workflow contains a mutable action reference"
fi
if grep -Eq '^[[:space:]]+push:[[:space:]]+true([[:space:]]+#.*)?$' "$workflow"; then
  fail "build action publishes before verification"
fi

test_line="$(line_of 'Run repository tests')"
build_line="$(line_of 'Build image once locally')"
scan_line="$(line_of 'Scan the exact local image')"
sbom_line="$(line_of 'Generate the exact local image SBOM')"
push_line="$(line_of 'Push the already-tested image once')"
resolve_line="$(line_of 'Resolve the immutable ECR digest')"
sign_line="$(line_of 'Attach SBOM and keylessly sign the immutable digest')"

(( test_line < build_line )) || fail "tests must run before the build"
(( build_line < scan_line )) || fail "scan must consume the already-built image"
(( scan_line < sbom_line )) || fail "SBOM must follow a successful scan"
(( sbom_line < push_line )) || fail "publication must follow tests, scan, and SBOM"
(( push_line < resolve_line )) || fail "digest must be resolved after the one push"
(( resolve_line < sign_line )) || fail "signature must target the resolved digest"

build_count="$(grep -Fc 'docker/build-push-action@' "$workflow")"
[[ "$build_count" == "1" ]] || fail "expected exactly one image build, found $build_count"

echo "ci-contract: PASS"
