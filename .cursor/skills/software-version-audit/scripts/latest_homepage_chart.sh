#!/usr/bin/env bash
# Print the newest homepage chart version from the Helm index of the
# HelmRepository declared in git (kubernetes/apps/homepage/repository.yaml),
# so the source of truth stays the manifest. Override with
# HOMEPAGE_CHART_INDEX=<index.yaml url>.
# Helm index.yaml: chart key at two spaces; entries are "- " list items.
set -euo pipefail

index_url="${HOMEPAGE_CHART_INDEX:-}"
if [[ -z "$index_url" ]]; then
  repo_root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
  manifest="$repo_root/kubernetes/apps/homepage/repository.yaml"
  if [[ ! -f "$manifest" ]]; then
    echo "lookup failed: $manifest not found (homepage HelmRepository moved?)" >&2
    exit 1
  fi
  base_url="$(awk '$1 == "url:" { print $2; exit }' "$manifest")"
  if [[ -z "$base_url" ]]; then
    echo "lookup failed: no url: in $manifest" >&2
    exit 1
  fi
  index_url="${base_url%/}/index.yaml"
fi

version="$(
  curl -fsSL "$index_url" | awk '
    /^  homepage:/ { in_chart=1; next }
    in_chart && /^  [a-zA-Z0-9_-]+:$/ { exit }
    in_chart && /^  - / && !entry {
      entry=1
      if (match($0, /version:[[:space:]]*/)) {
        print substr($0, RSTART + RLENGTH)
        exit
      }
    }
    in_chart && entry && /^    version:/ { print $2; exit }
  '
)"

if [[ -z "${version}" ]]; then
  echo "lookup failed: no homepage chart version in index" >&2
  exit 1
fi

printf '%s\n' "$version"
