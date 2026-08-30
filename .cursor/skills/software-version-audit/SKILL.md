---
name: software-version-audit
description: >-
  Audits declared, resolved, running, and upstream software versions across this
  homelab repo (Terraform, Ansible, Flux/Kubernetes, Talos, Docker). Use when the user
  asks for a version inventory, software audit, upgrade report, what's outdated,
  or latest available versions for homelab components.
---

# Software Version Audit

Produce an accurate version inventory for this homelab repository. Compare **declared in git**, **resolved/locked**, **running** (if accessible), and **latest stable** upstream.

Before lookups, read [reference.md](reference.md) and prefer the scripts under `scripts/` for fragile version queries.

## Workflow checklist

```
- [ ] 1. Scan repo for version pins (see Repo map below)
- [ ] 2. Classify each pin: exact / semver-range / floating
- [ ] 3. Read reference.md; query upstream via scripts or canonical sources
- [ ] 4. Query live cluster/hosts if access is available
- [ ] 5. Validate results before publishing (see Validation)
- [ ] 6. Write report grouped by deployment surface
```

## Repo map — where pins live

| Surface | Paths | What to extract |
|---|---|---|
| Terraform | `infra/terraform/*/` (one dir per stack) — `terraform.tf`, `.terraform-version`, `.terraform.lock.hcl` | CLI pin, provider constraints, locked provider versions |
| Ansible toolchain | `infra/ansible/requirements.txt` | `ansible`, `ansible-core` pins |
| Ansible Galaxy roles | `infra/ansible/requirements.yml` | Role name + version/ref |
| Ansible services | `infra/ansible/group_vars/` (extensionless), `infra/ansible/playbooks/` | `*_version`, `image:`, `tag:` |
| Flux bundle | `find kubernetes -name gotk-components.yaml` (don't hardcode the cluster path) | Flux version + controller image tags |
| Helm charts | HelmRelease objects — discover by kind (below) | `chart.spec.version` (exact or range) |
| Flux sources | GitRepository / HelmRepository objects — discover by kind (below) | `ref.tag` / `ref.branch`; chart repo `url` |
| App values | HelmRelease `values:`, CronJob/Pod specs | Container `image:` / `tag:` |
| Talos OS | `infra/metal/talos-version`, `infra/metal/patches/machine-install-image.yaml` | Exact OS tag; factory installer tag must match (CI: `scripts/check-talos-version.sh`). Kubernetes version is not pinned here. |

Discover Flux objects by top-level `kind:`, never by filename glob — names vary (`operator-release.yaml`, `operator-repository.yaml`) and globs go stale silently:

```bash
rg -l '^kind: HelmRelease$' kubernetes
rg -l '^kind: (GitRepository|HelmRepository)$' kubernetes
```

Anchor the pattern: unanchored matches also hit Flux CRD schema and embedded GVKs in `gotk-components.yaml`.

Do not conflate **chart version**, **appVersion**, **Ansible role version**, and **container image tag**. For Helm `^` / range pins, **Declared** is the constraint; **Resolved/Locked** comes from cluster HelmRelease status (or lockfile) when available — never treat the constraint string as the resolved version.

## Pin types

Classify every component before comparing versions:

- **Exact** — e.g. `2.2.0`, `v3.5.3`
- **Semver range** — e.g. `^1.19.0` — also note the highest version allowed by the constraint
- **Floating** — `latest`, no tag, or role ref `master`/`main` — mark **"not versioned in git"** unless runtime is queried

## Lookup rules — canonical sources

Use the right source per artifact. Never guess. Prefer `scripts/` when listed.

| Artifact | Source | Notes |
|---|---|---|
| Terraform providers | `scripts/latest_tf_provider.py` | Stable `x.y.z` only; numeric sort. **Never use `.versions[-1]` unsorted.** |
| Terraform CLI | HashiCorp Checkpoint API (default); `gh release view --repo hashicorp/terraform` if Checkpoint fails | Latest stable, not pre-release |
| Helm charts | Artifact Hub `/api/v1/packages/helm/{repo}/{chart}` | Direct package endpoint |
| Homepage chart | `scripts/latest_homepage_chart.sh` | index from the HelmRepository in git — not Artifact Hub search |
| GitHub releases/tags | `scripts/latest_github_semver.sh` (or authenticated `gh`) | **Use authenticated `gh`**, not unauthenticated curl |
| PyPI packages | `pypi.org/pypi/{package}/json` | Ansible toolchain |
| Ansible Galaxy roles | `galaxy.ansible.com/api/v1/roles/` | Role version ≠ app version; sort versions numerically (API order is not reliable) |
| Garage | `git.deuxfleurs.fr` API; declared tag from `kubernetes/apps/garage/repository.yaml` | Not github.com |
| Container apps | GitHub/container release tag tied to image | Avoid Docker Hub "latest tags" API — unreliable |
| Filebeat/Elastic | Elastic beats GitHub releases (default); artifacts HEAD only as fallback | Role may use a loose major (e.g. `8.x`) in `group_vars/all` |

### Homelab-specific sources (paths, not versions)

- Homepage chart index: derived by the script from `url:` in `kubernetes/apps/homepage/repository.yaml`
- Garage GitRepository: `kubernetes/apps/garage/repository.yaml` — read `url:` and `ref.tag` from the manifest
- Terraform providers per stack: `rg -n 'source\s*=' infra/terraform/*/terraform.tf`; resolved versions in each stack's `.terraform.lock.hcl`

## Live runtime queries (when cluster/host access available)

If unavailable, label **Running: N/A** and state that explicitly.

```bash
flux get helmreleases -A
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.spec.containers[*].image}{"\n"}{end}' | sort -u
talosctl version          # or equivalent for cluster OS/K8s
terraform version
```

For Ansible Docker hosts, running image versions require host access (`docker inspect` / `docker ps`).

## Validation — run before publishing

- If `latest stable < declared`, recheck the source and sort logic
- If latest jumped ≥1 major, verify source and report **both** overall latest stable and **same-major latest**
- If two sources disagree, prefer the canonical source and note the conflict
- Sanity-check against live upstream (not memorized majors): one Terraform provider, Flux bundle, one Helm chart
- Failed lookups → mark **"lookup failed"**, do not invent a version
- Huge gaps → verify the declared value's meaning (Ansible var vs binary vs chart vs image tag)

## Report format

Prefer the markdown tables below (this skill owns the deliverable). Do not switch to a Cursor canvas unless the user asks for one.

Group by deployment surface:

1. Infrastructure tooling (Terraform, Ansible)
2. Flux / GitOps
3. Kubernetes Helm charts & app pins
4. Ansible-managed services & Docker images
5. Ansible Galaxy roles

A surface discovered during the scan that fits no group gets its own numbered section — never silently fold it in or drop it.

### Row template

| Component | Declared | Resolved/Locked | Running | Latest stable | Latest same major | Pin type | Status | Source |

**Status values:** Current / Behind / Floating / Lookup failed / Major available

### Example row

| Component | Declared | Resolved/Locked | Running | Latest stable | Latest same major | Pin type | Status | Source |
|---|---|---|---|---|---|---|---|---|
| cert-manager chart | `^1.19.0` | `1.19.2` (cluster) | N/A | `1.20.1` | `1.19.2` | Semver range | Behind | Artifact Hub jetstack/cert-manager |
| prom/prometheus | (untagged) | N/A | N/A | `3.5.0` | — | Floating | Floating | GitHub prometheus/prometheus |

Use concrete queried versions in every cell (as above). Never write range placeholders like `1.19.x` or `3.x.y` in the report.

### End sections (required)

- **Biggest gaps** — prioritized: security patches, exact pins far behind, floating images
- **Not in repo** — components with no declared version (e.g. Kubernetes if unpinned)
- **Methodology** — sources used, whether `gh` auth was used, cluster queried or not, timestamp

## Components commonly unpinned in this repo

Treat separately; do not imply precision without runtime data. The bullets say where floating-pin traps cluster; derive the current set each run:

```bash
# Untagged images (no ':' at all) — pair with the :latest check, which is also floating.
# --no-filename matters: a 'path:' prefix would make grep -v ':' drop every line.
rg -oN --no-filename 'image:\s*(\S+)' -r '$1' infra/ansible/playbooks | grep -v ':' | sort -u
rg -n ':latest' infra/ansible kubernetes
# CronJobs (then inspect each one's image tags)
rg -l '^kind: CronJob$' kubernetes
# Compose templates (rg respects .gitignore; plain find hits venv/ noise)
rg --files infra/ansible -g '*compose*'
# Galaxy roles on a branch
rg -n '(version|ref):\s*(master|main)\b' infra/ansible/requirements.yml
```

- Docker images without tags under `infra/ansible/playbooks/docker-services/`
- Media-stack compose template (mix of untagged and `:latest` images)
- CronJob floating tags (e.g. `curlimages/curl:latest`)
- Galaxy roles on `master`/`main` in `infra/ansible/requirements.yml`

## Same-major comparisons

When latest stable is a different major than declared, always fill **Latest same major**. Derive majors from the declared pin in git — do not hardcode expected majors from memory.

## Additional reference

- Commands and API patterns: [reference.md](reference.md)
- Scripts: see `scripts/` — each is referenced from the Lookup rules table at its point of use
