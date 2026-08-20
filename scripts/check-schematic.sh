#!/usr/bin/env bash
# Verify that the schematic ID documented in infra/metal/schematic.yaml matches
# the ID the Talos Image Factory computes for the schematic body. The ID is a
# content hash of the body, so this catches the two drifting apart. Used by CI
# (.github/workflows/metal.yaml).
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
file="infra/metal/schematic.yaml"

# The ID appears twice (the Schematic ID comment and the installer image
# reference); require every occurrence to agree so neither can drift stale.
documented_ids="$(grep -oE '[0-9a-f]{64}' "${file}" | sort -u)" || true
if [ -z "${documented_ids}" ]; then
  echo "error: no schematic ID found in ${file}" >&2
  exit 1
fi
if [ "$(printf '%s\n' "${documented_ids}" | wc -l)" -ne 1 ]; then
  echo "error: ${file} references more than one schematic ID:" >&2
  printf '  %s\n' ${documented_ids} >&2
  exit 1
fi
expected="${documented_ids}"

# Separate a factory outage from genuine drift so a red check is diagnosable.
if ! response="$(grep -v '^#' "${file}" \
  | curl -sSf --max-time 30 --retry 3 -X POST --data-binary @- \
      https://factory.talos.dev/schematics)"; then
  echo "error: factory.talos.dev unreachable — cannot verify the schematic ID" >&2
  exit 1
fi
actual="$(printf '%s' "${response}" | jq -r '.id // empty')"
if [ -z "${actual}" ]; then
  echo "error: unexpected response from factory.talos.dev: ${response}" >&2
  exit 1
fi

if [ "${expected}" != "${actual}" ]; then
  echo "schematic ID mismatch in ${file}:" >&2
  echo "  documented: ${expected}" >&2
  echo "  computed:   ${actual}" >&2
  exit 1
fi
echo "schematic ID verified: ${actual}"
