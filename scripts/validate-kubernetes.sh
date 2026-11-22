#!/usr/bin/env bash
# Validate the Flux kustomize trees: build each entry point with kustomize,
# check every resource against its schema with kubeconform, and verify that
# every Flux source/reconciler is covered by a Flux Alert and every
# ExternalSecret's namespace is allowed by its ClusterSecretStore.
#
# Used by CI (.github/workflows/kubernetes.yaml) and the pre-commit hook.
#
# Schema sources, in lookup order:
#   1. kubeconform's default catalog (core Kubernetes types)
#   2. Flux CRD schemas, pinned to FluxInstance.spec.distribution.version in
#      kubernetes/clusters/homelab/flux-system/flux-instance.yaml
#   3. the datree CRDs-catalog (FluxInstance / fluxcd.controlplane.io, and
#      every other CR)
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
flux_instance=kubernetes/clusters/homelab/flux-system/flux-instance.yaml
flux_version="v$(awk '
  /^  distribution:/ { in_distribution = 1; next }
  /^  [a-zA-Z]/      { in_distribution = 0 }
  in_distribution && /^    version:/ { gsub(/"/, "", $2); print $2; exit }
' "${flux_instance}")" || true
if ! [[ "${flux_version}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: could not read an exact Flux version from ${flux_instance}" >&2
  echo "       (got '${flux_version}'; spec.distribution.version must be pinned," >&2
  echo "       e.g. \"2.9.4\", not a range like \"2.9.x\")" >&2
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

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT
all_yaml="${work_dir}/all.yaml"
: > "${all_yaml}"

rc=0
build_failed=0
for tree in "${trees[@]}"; do
  echo "==> ${tree}"
  tree_yaml="${work_dir}/tree.yaml"
  if build "${tree}" > "${tree_yaml}"; then
    printf '\n---\n' >> "${all_yaml}"
    cat "${tree_yaml}" >> "${all_yaml}"
    kubeconform \
      -strict \
      -summary \
      -cache "${kubeconform_cache}" \
      -skip CustomResourceDefinition,DiskPool,VLAgent \
      -schema-location default \
      -schema-location "${schema_dir}" \
      -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
      < "${tree_yaml}" \
      || rc=1
  else
    rc=1
    build_failed=1
  fi
done

# Flux Alert.spec.eventSources does not support namespace: "*" (omitting
# namespace matches only the Alert's own namespace). Verify that every Flux
# source and reconciler across all trees (including FluxInstance.spec.sync) is
# covered by an active, unfiltered Alert eventSource.
if [ "${build_failed}" -eq 0 ]; then
  echo "==> flux alert coverage"
  awk '
    function parse_kv(line, kv,    idx, v) {
      sub(/^[ \t]+(-[ \t]+)?/, "", line)
      idx = index(line, ":")
      if (idx == 0) return 0
      kv["k"] = substr(line, 1, idx - 1)
      v = substr(line, idx + 1)
      gsub(/^[ \t]+|[ \t]+$/, "", v)
      if ((v ~ /^".*"$/) || (v ~ /^\047.*\047$/)) v = substr(v, 2, length(v) - 2)
      kv["v"] = v
      return 1
    }
    function flush_es() {
      if (in_es_item && es_kind != "" && es_name != "" && !es_has_labels) {
        doc_es[++doc_es_n] = es_kind SUBSEP es_ns SUBSEP es_name
      }
      in_es_item = es_has_labels = 0
      es_kind = es_name = es_ns = ""
    }
    function flush_doc(    eff_ns, eff_sync, i, e) {
      flush_es()
      eff_ns = (ns != "" ? ns : "default")
      if (api ~ /\.toolkit\.fluxcd\.io\// &&
          kind ~ /^(GitRepository|OCIRepository|Bucket|HelmRepository|HelmChart|Kustomization|HelmRelease|ImageRepository|ImagePolicy|ImageUpdateAutomation)$/) {
        needed[kind, eff_ns, name] = 1
      } else if (api ~ /^fluxcd\.controlplane\.io\// && kind == "FluxInstance" && sync_kind != "") {
        eff_sync = (sync_name != "" ? sync_name : eff_ns)
        needed[sync_kind, eff_ns, eff_sync] = 1
        needed["Kustomization", eff_ns, eff_sync] = 1
      } else if (api ~ /^notification\.toolkit\.fluxcd\.io\// && kind == "Alert" &&
                 !alert_suspended && !alert_filtered) {
        for (i = 1; i <= doc_es_n; i++) {
          split(doc_es[i], e, SUBSEP)
          covered[e[1], (e[2] != "" ? e[2] : eff_ns), e[3]] = 1
        }
      }
      api = kind = ns = name = section = subsec = sync_kind = sync_name = ""
      doc_es_n = alert_suspended = alert_filtered = 0
    }
    /^---/ { flush_doc(); next }
    /^[a-zA-Z]/ {
      flush_es()
      section = subsec = ""
      if (parse_kv($0, kv)) {
        if (kv["k"] == "apiVersion") api = kv["v"]
        else if (kv["k"] == "kind") kind = kv["v"]
        else if (kv["k"] == "metadata" || kv["k"] == "spec") section = kv["k"]
      }
      next
    }
    section == "metadata" && /^  [a-zA-Z]/ && parse_kv($0, kv) {
      if (kv["k"] == "name") name = kv["v"]
      else if (kv["k"] == "namespace") ns = kv["v"]
      next
    }
    section == "spec" && /^  [a-zA-Z]/ {
      flush_es()
      subsec = ""
      if (parse_kv($0, kv)) {
        if (kind == "FluxInstance" && kv["k"] == "sync") subsec = "sync"
        else if (kind == "Alert") {
          if (kv["k"] == "eventSources") subsec = "eventSources"
          else if (kv["k"] == "suspend" && kv["v"] == "true") alert_suspended = 1
          else if (kv["k"] == "inclusionList" && kv["v"] != "[]") alert_filtered = 1
        }
      }
      next
    }
    subsec == "sync" && /^    [a-zA-Z]/ && parse_kv($0, kv) {
      if (kv["k"] == "kind") sync_kind = kv["v"]
      else if (kv["k"] == "name") sync_name = kv["v"]
      next
    }
    subsec == "eventSources" {
      if (/^[ \t]+-[ \t]+/) { flush_es(); in_es_item = 1 }
      if (in_es_item && parse_kv($0, kv)) {
        if (kv["k"] == "kind") es_kind = kv["v"]
        else if (kv["k"] == "name") es_name = kv["v"]
        else if (kv["k"] == "namespace") es_ns = kv["v"]
        else if (kv["k"] == "matchLabels" && kv["v"] != "{}") es_has_labels = 1
      }
    }
    END {
      flush_doc()
      err_sort = "sort >&2"
      for (k in needed) {
        split(k, p, SUBSEP)
        pair = p[1] SUBSEP p[2]
        if (!((pair SUBSEP "*") in covered) && !(k in covered) && !(pair in reported)) {
          reported[pair] = 1
          printf "error: %s in namespace %s is not covered by any Flux Alert eventSources\n", p[1], p[2] | err_sort
          missing = 1
        }
      }
      if (missing) {
        close(err_sort)
        print "       add it to kubernetes/apps/observability/flux/alert.yaml" | "cat >&2"
        close("cat >&2")
        exit 1
      }
      print "Summary: all Flux resources covered by Alert eventSources"
    }
  ' "${all_yaml}" || rc=1
else
  echo "==> flux alert coverage (skipped: kustomize build failed)"
fi

# A ClusterSecretStore with spec.conditions refuses ExternalSecrets from
# unlisted namespaces. Verify every ExternalSecret's namespace is listed in
# spec.conditions[].namespaces of the ClusterSecretStore it references
# (namespaceSelector/namespaceRegexes are not evaluated here).
if [ "${build_failed}" -eq 0 ]; then
  echo "==> cluster secret store namespace conditions"
  awk '
    function val(line) {
      sub(/^[^:]*:[ \t]*/, "", line)
      gsub(/^["\047]|["\047][ \t]*$/, "", line)
      return line
    }
    function flush() {
      if (kind == "ExternalSecret" && store_kind == "ClusterSecretStore")
        used[store, (ns != "" ? ns : "default"), name] = 1
      kind = ns = name = store = store_kind = section = sub_section = ""
    }
    /^---/ { flush(); next }
    /^kind:/ { kind = val($0) }
    /^[a-zA-Z]/ { section = $1; sub_section = ""; next }
    section == "metadata:" && /^  name:/ { name = val($0) }
    section == "metadata:" && /^  namespace:/ { ns = val($0) }
    section == "spec:" && /^  [a-zA-Z]/ { sub_section = $1 }
    sub_section == "secretStoreRef:" && /^    kind:/ { store_kind = val($0) }
    sub_section == "secretStoreRef:" && /^    name:/ { store = val($0) }
    kind == "ClusterSecretStore" && sub_section == "conditions:" && /^ +- [a-z0-9-]+$/ {
      if (name != "") { v = $0; sub(/^ +- /, "", v); allowed[name, v] = 1 }
    }
    kind == "ClusterSecretStore" && section == "spec:" && /^  conditions:/ { conditioned[name] = 1 }
    END {
      flush()
      for (k in used) {
        split(k, p, SUBSEP)
        if ((p[1] in conditioned) && !((p[1], p[2]) in allowed)) {
          printf "error: ExternalSecret %s/%s uses ClusterSecretStore %s, whose spec.conditions do not list namespace %s\n", p[2], p[3], p[1], p[2] | "sort >&2"
          missing = 1
        }
      }
      close("sort >&2")
      if (missing) exit 1
      print "Summary: all ExternalSecret namespaces allowed by their ClusterSecretStore"
    }
  ' "${all_yaml}" || rc=1
else
  echo "==> cluster secret store namespace conditions (skipped: kustomize build failed)"
fi
exit "${rc}"
