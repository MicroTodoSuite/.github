#!/usr/bin/env bash
# Holds every organization-owned workflow to the reviewed Node.js 24 checkout release.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
expected_checkout_sha="3d3c42e5aac5ba805825da76410c181273ba90b1"

failures=0
references=0

fail() {
  printf 'github-actions-runtime: FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}

while IFS= read -r workflow; do
  while IFS=: read -r line_number checkout_reference; do
    [[ -n "$checkout_reference" ]] || continue
    references=$((references + 1))
    checkout_sha="${checkout_reference##*@}"

    [[ "$checkout_sha" =~ ^[0-9a-f]{40}$ ]] \
      || fail "$workflow:$line_number must pin actions/checkout by a full commit SHA"
    [[ "$checkout_sha" == "$expected_checkout_sha" ]] \
      || fail "$workflow:$line_number must use the reviewed Node.js 24 checkout SHA $expected_checkout_sha"
  done < <(grep -nEo 'actions/checkout@[^[:space:]#]+' "$repo_root/$workflow" || true)
done < <(git -C "$repo_root" ls-files '.github/workflows/*.yml' '.github/workflows/*.yaml')

[[ "$references" -gt 0 ]] || fail "repository workflows must contain at least one actions/checkout reference"

if [[ "$failures" -gt 0 ]]; then
  printf 'github-actions-runtime: FAIL: %d violation(s)\n' "$failures" >&2
  exit 1
fi

printf 'github-actions-runtime: PASS: all %d checkout references use the reviewed Node.js 24 SHA.\n' "$references"
