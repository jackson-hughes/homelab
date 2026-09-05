#!/usr/bin/env bash
# Print one Terraform stack directory per line: infra/* with a
# .terraform-version pin. Used by CI (.github/workflows/terraform.yaml) and the
# pre-commit terraform-fmt hook so a new stack is picked up without editing
# those lists.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

found=0
for d in infra/*/; do
  [ -f "${d}.terraform-version" ] || continue
  printf '%s\n' "${d%/}"
  found=1
done

if [ "${found}" -eq 0 ]; then
  echo "error: no Terraform stacks found under infra/*/ with .terraform-version" >&2
  exit 1
fi
