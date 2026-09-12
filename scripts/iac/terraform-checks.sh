#!/usr/bin/env bash
# Runs terraform init without a backend in every module, sample, and root, then:
#   module: terraform test, which validates the module in the context its tests
#           give it. Terraform 1.15 rejects `terraform validate` on a module that
#           declares configuration_aliases, so the module is not validated alone.
#   sample and root: terraform validate, then terraform test when tests exist.
# Usage: terraform-checks.sh modules|live   (from the directory to check)
set -euo pipefail

kind="${1:?usage: terraform-checks.sh modules|live}"
failures=0

# check_directory DIRECTORY [validate|no-validate]
check_directory() {
  local directory="$1" validate="${2:-validate}"
  echo "::group::$directory"
  if ! terraform -chdir="$directory" init -backend=false -input=false -no-color >/dev/null; then
    echo "::error::terraform init failed in $directory"
    failures=$((failures + 1))
  elif [ "$validate" = validate ] && ! terraform -chdir="$directory" validate -no-color; then
    echo "::error::terraform validate failed in $directory"
    failures=$((failures + 1))
  elif compgen -G "$directory/tests/*.tftest.hcl" >/dev/null \
    && ! terraform -chdir="$directory" test -no-color; then
    echo "::error::terraform test failed in $directory"
    failures=$((failures + 1))
  fi
  echo "::endgroup::"
}

case "$kind" in
  modules)
    for directory in */; do
      directory="${directory%/}"
      case "$directory" in .* | _*) continue ;; esac
      compgen -G "$directory/*.tf" >/dev/null || continue
      check_directory "$directory" no-validate
      if [ -d "$directory/sample" ]; then
        check_directory "$directory/sample"
      fi
    done
    ;;
  live)
    while IFS= read -r directory; do
      check_directory "$directory"
    done < <(find . -name '*.tf' -not -path '*/.*' -not -path '*/fixtures/*' \
      -not -path '*/modules/*' -printf '%h\n' | sort -u)
    ;;
  *)
    echo "::error::kind must be modules or live, not '$kind'"
    exit 2
    ;;
esac

if [ "$failures" -ne 0 ]; then
  echo "terraform-checks: $failures directory(ies) failed" >&2
  exit 1
fi
echo "terraform-checks: every directory passed"
