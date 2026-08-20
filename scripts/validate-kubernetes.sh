#!/usr/bin/env bash
# Validate the Flux kustomize trees: build each entry point with kustomize and
# check every resource against its schema with kubeconform.
#
# Used by CI (.github/workflows/kubernetes.yaml) and the pre-commit hook.
#
# Schema sources, in lookup order:
#   1. kubeconform's default catalog (core Kubernetes types)
#   2. Flux CRD schemas, pinned to the Flux version deployed in
#      kubernetes/clusters/homelab/flux-system/gotk-components.yaml
#   3. the datree CRDs-catalog (all other CRs)
#
# Skipped kinds (extend this list rather than reaching for
# -ignore-missing-schemas, which would also silently skip misspelled kinds):
#   CustomResourceDefinition  no strict-mode schema exists; the Flux docs'
#                             validate script skips it too
#   DiskPool                  the datree catalog only carries openebs.io
#                             v1beta2 and the repo uses v1beta3; retire the
#                             skip if diskpool_v1beta3.json appears upstream
#   VLAgent                   datree's schema is stale: it rejects
#                             spec.k8sCollector, which is valid in the deployed
#                             vm-operator chart (0.67.2)
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if command -v kustomize >/dev/null; then
  build() { kustomize build "$1"; }
elif command -v kubectl >/dev/null; then
  build() { kubectl kustomize "$1"; }
else
  echo "error: need kustomize or kubectl on PATH (brew install kustomize)" >&2
  exit 1
fi

if ! command -v kubeconform >/dev/null; then
  echo "error: kubeconform not found on PATH (brew install kubeconform)" >&2
  exit 1
fi

# Match the schemas to the Flux version actually running in the cluster.
flux_version="$(grep -m1 'app.kubernetes.io/version:' \
  kubernetes/clusters/homelab/flux-system/gotk-components.yaml | awk '{print $2}')" || true
if [ -z "${flux_version}" ]; then
  echo "error: could not determine the Flux version from gotk-components.yaml" >&2
  exit 1
fi

cache_root="${XDG_CACHE_HOME:-$HOME/.cache}"

# kubeconform resolves a directory schema-location using its default template,
# so the schemas must sit under master-standalone-strict/ inside it. Download
# to a temp dir and move into place atomically so an interrupted download
# can't leave a half-populated cache that later runs mistake for a warm one;
# _definitions.json is the sentinel proving the tarball extracted fully.
schema_dir="${cache_root}/flux-crd-schemas/${flux_version}"
if [ ! -f "${schema_dir}/master-standalone-strict/_definitions.json" ]; then
  echo "Downloading Flux ${flux_version} CRD schemas to ${schema_dir}"
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir}"' EXIT
  mkdir -p "${tmp_dir}/master-standalone-strict"
  curl -sfL "https://github.com/fluxcd/flux2/releases/download/${flux_version}/crd-schemas.tar.gz" \
    | tar xz -C "${tmp_dir}/master-standalone-strict"
  test -f "${tmp_dir}/master-standalone-strict/_definitions.json"
  rm -rf "${schema_dir}"
  mkdir -p "$(dirname "${schema_dir}")"
  mv "${tmp_dir}" "${schema_dir}"
  trap - EXIT
fi

# Cache the schemas kubeconform fetches over HTTP (core types and the datree
# catalog) so repeat runs are fast and work offline.
kubeconform_cache="${cache_root}/kubeconform-schemas"
mkdir -p "${kubeconform_cache}"

# The cluster entry point plus the spec.path of every Flux Kustomization it
# defines, derived so a new Kustomization gets validated without editing this
# script.
trees=(kubernetes/clusters/homelab)
while IFS= read -r flux_path; do
  trees+=("${flux_path#./}")
done < <(grep -h '^  path: \./' kubernetes/clusters/homelab/*.yaml | awk '{print $2}')
if [ "${#trees[@]}" -lt 2 ]; then
  echo "error: no Flux Kustomization spec.path entries found under kubernetes/clusters/homelab" >&2
  exit 1
fi

rc=0
for tree in "${trees[@]}"; do
  echo "==> ${tree}"
  build "${tree}" | kubeconform \
    -strict \
    -summary \
    -cache "${kubeconform_cache}" \
    -skip CustomResourceDefinition,DiskPool,VLAgent \
    -schema-location default \
    -schema-location "${schema_dir}" \
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
    || rc=1
done
exit "${rc}"
