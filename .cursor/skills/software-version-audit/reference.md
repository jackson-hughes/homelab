# Software Version Audit — Reference

Command snippets and API patterns for this homelab repo. Prefer `scripts/` for fragile lookups.

## Repo discovery

```bash
# Broad scan: every tracked file — no directory or extension whitelist to go stale,
# and git ls-files emits extensionless files (group_vars/*) as explicit paths.
# Expect a few self-referential hits (this skill's docs; Taskfile.yml's schema `version: '3'`).
# version: also matches *_version:; .tf/.hcl use version = — see Terraform pins below.
git ls-files -z | xargs -0 rg -n 'version:|tag:|image:'

# HelmReleases only (top-level kind; excludes CRD schema / embedded GVKs)
rg -l '^kind: HelmRelease$' kubernetes

# Terraform pins (finds every stack; do not hardcode the stack list)
rg 'required_version|version\s*=' infra/terraform --glob '*.tf'
find infra/terraform -name .terraform-version -exec grep -H . {} +
# Locked (resolved) provider versions — fills the Resolved/Locked column.
# Lockfiles are dotfiles, which rg's default filters may skip; find sidesteps that.
find infra/terraform -name .terraform.lock.hcl -exec grep -H -A1 '^provider ' {} +
```

## Scripts (preferred)

Run from the repo root:

```bash
SKILL=".cursor/skills/software-version-audit"

# Terraform providers: derive namespace/name and declared major from git first —
# never from memory. (^-anchored: unanchored version\s*= also matches required_version.)
rg -n 'source\s*=' infra/terraform/*/terraform.tf
rg -n '^\s*version\s*=' infra/terraform/*/terraform.tf
python3 "$SKILL/scripts/latest_tf_provider.py" hashicorp aws     # latest stable only
python3 "$SKILL/scripts/latest_tf_provider.py" hashicorp aws 5   # + same-major; "5" = major of the declared pin above

# Homepage chart (index URL read from kubernetes/apps/homepage/repository.yaml — not Artifact Hub)
bash "$SKILL/scripts/latest_homepage_chart.sh"

# GitHub semver via authenticated gh. Derive --major from the declared pin in git
# (e.g. rg -n '_version' infra/ansible/group_vars infra/ansible/playbooks), never from memory.
bash "$SKILL/scripts/latest_github_semver.sh" fluxcd/flux2
bash "$SKILL/scripts/latest_github_semver.sh" apache/kafka --tags
bash "$SKILL/scripts/latest_github_semver.sh" hashicorp/consul --major 1     # "1" from the consul_version pin
bash "$SKILL/scripts/latest_github_semver.sh" apache/kafka --tags --major 3  # "3" from the kafka_version pin
# --prefix filters to that tag family only (optional; not needed for leading v)
```

## Terraform CLI (default: Checkpoint)

```bash
curl -fsSL https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r .current_version
# Fallback if Checkpoint fails:
gh release view --repo hashicorp/terraform --json tagName -q .tagName
```

## Helm charts (Artifact Hub)

```bash
# Enumerate deployed charts from git first — never audit from a memorized list.
# Git-sourced chart paths in the output (e.g. script/helm/garage) are not on
# Artifact Hub; resolve those via their source repo instead.
rg -n --no-heading '^\s+chart: ' kubernetes --glob '!**/flux-system/**' | sort -u

# Then query each — syntax examples, not the full set:
curl -fsSL "https://artifacthub.io/api/v1/packages/helm/jetstack/cert-manager" | jq -r .version
curl -fsSL "https://artifacthub.io/api/v1/packages/helm/victoriametrics/victoria-metrics-k8s-stack" | jq -r .version
```

For Homepage, use `scripts/latest_homepage_chart.sh` only.

## PyPI & Galaxy

```bash
# The full pin set is requirements.txt — audit every line, not just ansible/ansible-core:
cat infra/ansible/requirements.txt
curl -fsSL https://pypi.org/pypi/ansible/json | jq -r .info.version
curl -fsSL https://pypi.org/pypi/ansible-core/json | jq -r .info.version

# Galaxy: do not trust versions[0] as newest — sort numerically
curl -fsSL "https://galaxy.ansible.com/api/v1/roles/?owner__username=geerlingguy&name=docker" \
  | jq -r '
      .results[0].summary_fields.versions
      | map(.name)
      | map(select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$")))
      | sort_by(split(".") | map(tonumber))
      | last
    '
```

## Forgejo (Garage)

Declared tag: read `kubernetes/apps/garage/repository.yaml`. Upstream — build the API URL from the manifest's `url:` (host + owner/repo); only the `/api/v1/repos/{owner}/{repo}/releases` path is Forgejo convention:

```bash
curl -fsSL 'https://git.deuxfleurs.fr/api/v1/repos/Deuxfleurs/garage/releases?limit=1' | jq -r '.[0].tag_name'
```

## Filebeat / Elastic (default: GitHub releases)

```bash
# --major from the declared pin: rg -n 'filebeat_version' infra/ansible/group_vars
bash .cursor/skills/software-version-audit/scripts/latest_github_semver.sh elastic/beats --major 8
# Fallback only: Elastic artifacts HEAD / package pages
```

## Flux / Kubernetes runtime

```bash
flux get helmreleases -A
flux get sources git -A
kubectl get pods -A -o custom-columns='NS:.metadata.namespace,IMAGE:.spec.containers[*].image' --no-headers | sort -u
```

For Helm range pins, take resolved chart version from `flux get helmreleases` / HelmRelease status, not from the constraint in git.

## Ansible Docker hosts

```bash
docker ps --format '{{.Names}}\t{{.Image}}'
docker inspect -f '{{.Config.Image}}' prometheus
```

## Validation heuristics

| Signal | Action |
|---|---|
| `latest stable < declared` | Recheck source and sort logic |
| Major version jump | Confirm canonical source; fill same-major column from declared major |
| Docker Hub tag looks wrong (e.g. prometheus `0.15.0`) | Switch to GitHub releases |
| GitHub 403 rate limit | Use authenticated `gh` / skill scripts, or wait/retry |
| Registry `.versions[-1]` ≠ expected | Use `scripts/latest_tf_provider.py` |
| GitHub tags `head -1` or API page order | Use `scripts/latest_github_semver.sh` |
| `gh release list` tabular output for same-major | Column 1 is release **title** (`name`), not `tagName` |
| Ansible `*_version` var | Confirm whether it's app binary, role default, or collection pin |
| Galaxy `versions[0]` | Sort numerically — API order is not reliable |
