#!/usr/bin/env bash
# Latest stable semver from GitHub via authenticated gh.
#
# Usage:
#   latest_github_semver.sh <owner/repo> [--tags|--releases] [--major N] [--prefix PREFIX]
#
# Defaults: --releases, no major filter. Leading "v" is stripped for compare
# unless --prefix is set. Output keeps the original winning tag.
#
# --prefix filters to that tag family only (non-matching tags are skipped), then
# strips the prefix before semver parse. Do not pass --prefix v — bare/v tags
# are handled by the default v-strip.
#
# Examples:
#   latest_github_semver.sh fluxcd/flux2
#   latest_github_semver.sh apache/kafka --tags
#   latest_github_semver.sh hashicorp/consul --major 1
#   latest_github_semver.sh apache/kafka --tags --major 3
#   latest_github_semver.sh some/repo --tags --prefix release-
set -euo pipefail

if [[ $# -lt 1 ]]; then
  sed -n '2,20p' "$0" >&2
  exit 2
fi

REPO="$1"
shift
MODE="releases"
MAJOR=""
PREFIX=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tags) MODE="tags"; shift ;;
    --releases) MODE="releases"; shift ;;
    --major)
      MAJOR="${2:?--major requires a value}"
      shift 2
      ;;
    --prefix)
      PREFIX="${2:?--prefix requires a value}"
      shift 2
      ;;
    *)
      echo "unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

if ! command -v gh >/dev/null 2>&1; then
  echo "lookup failed: gh not installed" >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
raw_file="$tmpdir/raw.txt"
err_file="$tmpdir/err.txt"
filtered_file="$tmpdir/filtered.txt"

# Fail closed on gh errors (auth, rate limit, pagination). Do not discard stderr.
set +e
if [[ "$MODE" == "releases" ]]; then
  # tag_name only; never use release title (name). Paginate — list order ≠ semver.
  gh api "repos/${REPO}/releases" --paginate \
    -q '.[] | select(.prerelease == false and .draft == false) | .tag_name' \
    >"$raw_file" 2>"$err_file"
  gh_status=$?
else
  gh api "repos/${REPO}/tags" --paginate -q '.[].name' \
    >"$raw_file" 2>"$err_file"
  gh_status=$?
fi
set -e

if [[ "$gh_status" -ne 0 ]]; then
  echo "lookup failed: gh api exited ${gh_status}" >&2
  if [[ -s "$err_file" ]]; then
    cat "$err_file" >&2
  fi
  exit 1
fi

if [[ ! -s "$raw_file" ]]; then
  echo "lookup failed: no tags/releases from gh" >&2
  exit 1
fi

: >"$filtered_file"
while IFS= read -r tag || [[ -n "${tag:-}" ]]; do
  [[ -z "${tag:-}" ]] && continue
  bare="$tag"
  if [[ -n "$PREFIX" ]]; then
    # Filter to this tag family only — do not fall through to default v-strip.
    if [[ "$bare" != "$PREFIX"* ]]; then
      continue
    fi
    bare="${bare#"$PREFIX"}"
  elif [[ "$bare" == v* ]]; then
    bare="${bare#v}"
  fi
  if [[ ! "$bare" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    continue
  fi
  maj="${bare%%.*}"
  rest="${bare#*.}"
  min="${rest%%.*}"
  pat="${rest#*.}"
  if [[ -n "$MAJOR" && "$maj" != "$MAJOR" ]]; then
    continue
  fi
  printf '%s %s %s %s\n' "$maj" "$min" "$pat" "$tag" >>"$filtered_file"
done <"$raw_file"

if [[ ! -s "$filtered_file" ]]; then
  echo "lookup failed: no matching stable semver tags" >&2
  exit 1
fi

sort -k1,1n -k2,2n -k3,3n "$filtered_file" | tail -1 | awk '{print $4}'
