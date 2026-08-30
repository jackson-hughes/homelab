#!/usr/bin/env bash
# Verify that the declared Talos version pin, factory installer image, and
# schematic extensions agree and that the Image Factory can build that
# combination. Used by CI (.github/workflows/metal.yaml). Does not talk to
# the cluster.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

pin_file="infra/metal/talos-version"
schematic_file="infra/metal/schematic.yaml"
image_patch="infra/metal/patches/machine-install-image.yaml"

if [ ! -f "${pin_file}" ]; then
  echo "error: ${pin_file} is missing" >&2
  exit 1
fi
pin="$(tr -d '[:space:]' < "${pin_file}")"
if [[ ! "${pin}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: ${pin_file} must be a stable tag like v1.13.9, got: ${pin}" >&2
  exit 1
fi

documented_ids="$(grep -oE '[0-9a-f]{64}' "${schematic_file}" | sort -u)" || true
if [ -z "${documented_ids}" ]; then
  echo "error: no schematic ID found in ${schematic_file}" >&2
  exit 1
fi
if [ "$(printf '%s\n' "${documented_ids}" | wc -l)" -ne 1 ]; then
  echo "error: ${schematic_file} references more than one schematic ID:" >&2
  printf '  %s\n' ${documented_ids} >&2
  exit 1
fi
schematic_id="${documented_ids}"

expected_image="factory.talos.dev/installer/${schematic_id}:${pin}"
actual_image="$(grep -oE 'factory\.talos\.dev/installer/[0-9a-f]{64}:v[0-9]+\.[0-9]+\.[0-9]+' "${image_patch}" | sort -u)" || true
if [ -z "${actual_image}" ]; then
  echo "error: no factory installer image found in ${image_patch}" >&2
  exit 1
fi
if [ "$(printf '%s\n' "${actual_image}" | wc -l)" -ne 1 ]; then
  echo "error: ${image_patch} references more than one factory installer image:" >&2
  printf '  %s\n' ${actual_image} >&2
  exit 1
fi
if [ "${actual_image}" != "${expected_image}" ]; then
  echo "error: installer image does not match ${pin_file} + ${schematic_file}:" >&2
  echo "  expected: ${expected_image}" >&2
  echo "  found:    ${actual_image}" >&2
  exit 1
fi

extensions=()
while IFS= read -r ext; do
  [ -n "${ext}" ] && extensions+=("${ext}")
done <<EOF
$(awk '
  /^[[:space:]]*#/ { next }
  $1 == "officialExtensions:" { in_ext=1; next }
  in_ext && $1 == "-" { print $2; next }
  in_ext && NF { exit }
' "${schematic_file}")
EOF
if [ "${#extensions[@]}" -eq 0 ]; then
  echo "error: no officialExtensions found in ${schematic_file}" >&2
  exit 1
fi

if ! versions_json="$(curl -sSf --max-time 30 --retry 3 https://factory.talos.dev/versions)"; then
  echo "error: factory.talos.dev/versions unreachable" >&2
  exit 1
fi
versions_type="$(printf '%s' "${versions_json}" | jq -r 'type')"
if [ "${versions_type}" != "array" ]; then
  echo "error: factory /versions returned ${versions_type}, expected array" >&2
  exit 1
fi
if ! printf '%s' "${versions_json}" | jq -e --arg pin "${pin}" '
  (map(select(type == "string")) | index($pin)) != null
' >/dev/null; then
  echo "error: ${pin} is not a published Talos version on factory.talos.dev" >&2
  exit 1
fi

if ! ext_json="$(curl -sSf --max-time 30 --retry 3 \
  "https://factory.talos.dev/version/${pin}/extensions/official")"; then
  echo "error: factory.talos.dev unreachable for ${pin} official extensions" >&2
  exit 1
fi
ext_type="$(printf '%s' "${ext_json}" | jq -r 'type')"
if [ "${ext_type}" != "array" ]; then
  echo "error: factory official extensions returned ${ext_type}, expected array" >&2
  exit 1
fi

missing=0
for ext in "${extensions[@]}"; do
  if ! printf '%s' "${ext_json}" | jq -e --arg name "${ext}" 'any(.name == $name)' >/dev/null; then
    echo "error: schematic extension ${ext} is not available for ${pin}" >&2
    missing=1
  fi
done
if [ "${missing}" -ne 0 ]; then
  exit 1
fi

echo "talos version pin verified: ${pin}"
echo "installer image: ${actual_image}"
printf 'extensions: %s\n' "${extensions[*]}"
