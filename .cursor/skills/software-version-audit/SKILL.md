---
name: software-version-audit
description: >-
  Audits declared, resolved, running, and upstream software versions across this
  homelab repo (Terraform, Ansible, Flux/Kubernetes, Docker). Use when the user
  asks for a version inventory, software audit, upgrade report, what's outdated,
  or latest available versions for homelab components.
---

# Software Version Audit

Produce an accurate version inventory for this homelab repository. Compare **declared in git**, **resolved/locked**, **running** (if accessible), and **latest upstream**.

## Workflow checklist

```
- [ ] 1. Scan repo for version pins (see Repo map below)
- [ ] 2. Classify each pin: exact / semver-range / floating
- [ ] 3. Query upstream using canonical sources (see Lookup rules)
- [ ] 4. Query live cluster/hosts if access is available
- [ ] 5. Validate results before publishing (see Validation)
- [ ] 6. Write report grouped by deployment surface
```

## Repo map — where pins live

| Surface | Paths | What to extract |
|---|---|---|
| Terraform | `infra/terraform/**`, `.terraform-version`, `.terraform.lock.hcl` | CLI version, provider constraints, locked provider versions |
| Ansible toolchain | `infra/ansible/requirements.txt` | `ansible`, `ansible-core` pins |
| Ansible Galaxy roles | `infra/ansible/requirements.yml` | Role name + version/ref |
| Ansible services | `infra/ansible/group_vars/`, `infra/ansible/playbooks/` | `*_version`, `image:`, `tag:` |
| Flux bundle | `kubernetes/clusters/homelab/flux-system/gotk-components.yaml` | Flux version + controller image tags |
| Helm charts | `kubernetes/**/release.yaml` | `chart.version` constraints |
| Git sources | `kubernetes/**/repository.yaml` | `ref.tag`, `ref.branch` |
| App values | HelmRelease `values:`, CronJob/Pod specs | Container `image:` / `tag:` |
| Talos | `infra/metal/patches/` | Machine patches only — **cluster OS/K8s version may not be pinned here** |

## Pin types

Classify every component before comparing versions:

- **Exact** — e.g. `2.2.0`, `v3.5.3`, `1.22.5`
- **Semver range** — e.g. `^1.19.0` — also note the highest version allowed by the constraint
- **Floating** — `latest`, no tag, or role ref `master`/`main` — mark **"not versioned in git"** unless runtime is queried

Do not conflate **chart version**, **appVersion**, **Ansible role version**, and **container image tag**.

## Lookup rules — canonical sources

Use the right source per artifact. Never guess.

| Artifact | Source | Notes |
|---|---|---|
| Terraform providers | `registry.terraform.io/v1/providers/{namespace}/{name}/versions` | Filter stable `x.y.z`, sort numerically. **Never use `.versions[-1]` unsorted.** |
| Terraform CLI | HashiCorp Checkpoint API or `gh release list --repo hashicorp/terraform` | Prefer latest stable, not pre-release |
| Helm charts | Artifact Hub ` /api/v1/packages/helm/{repo}/{chart}` | Direct package endpoint |
| GitHub releases/tags | `gh api` / `gh release view` | **Use authenticated `gh`**, not unauthenticated curl. Tag lists are not semver-ordered — sort numerically before picking latest |
| PyPI packages | `pypi.org/pypi/{package}/json` | Ansible toolchain |
| Ansible Galaxy roles | `galaxy.ansible.com/api/v1/roles/` | Role version ≠ app version |
| Garage | `git.deuxfleurs.fr` API or repo tag from `kubernetes/apps/garage/repository.yaml` | Not github.com |
| Container apps | GitHub/container release tag tied to image | Avoid Docker Hub "latest tags" API — unreliable |
| Filebeat/Elastic | Elastic artifacts HEAD check or beats releases | Role uses `8.x` loosely in `group_vars/all` |

### Known homelab-specific sources

- Homepage chart: `jameswynn.github.io/helm-charts` (not generic Artifact Hub search results)
- Garage GitRepository: `https://git.deuxfleurs.fr/Deuxfleurs/garage.git` tag `v2.3.0`
- AWS provider pinned in `infra/terraform/aws/terraform.tf` — expect 5.x in repo; upstream is 6.x

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

- If `latest < declared`, recheck the source
- If latest jumped ≥1 major, verify source and report **both** overall latest and **same-major latest**
- If two sources disagree, prefer the canonical source and note the conflict
- Sanity-check: Terraform AWS provider (expect 6.x latest), Flux bundle, one Helm chart
- Failed lookups → mark **"lookup failed"**, do not invent a version
- Huge gaps (e.g. node_exporter `1.3.1` vs upstream `1.11.x`) → verify the declared value's meaning (Ansible var vs binary)

## Report format

Group by deployment surface:

1. Infrastructure tooling (Terraform, Ansible)
2. Flux / GitOps
3. Kubernetes Helm charts & app pins
4. Ansible-managed services & Docker images
5. Ansible Galaxy roles

### Row template

| Component | Declared | Resolved/Locked | Running | Latest stable | Latest same major | Pin type | Status | Source |

**Status values:** Current / Behind / Floating / Lookup failed / Major available

### End sections (required)

- **Biggest gaps** — prioritized: security patches, exact pins far behind, floating images
- **Not in repo** — components with no declared version (e.g. Talos/K8s if unpinned)
- **Methodology** — sources used, whether `gh` auth was used, cluster queried or not, timestamp

## Components commonly unpinned in this repo

Treat separately; do not imply precision without runtime data:

- Docker: `prom/prometheus`, `grafana/grafana`, `prom/alertmanager`, `prom/consul-exporter`, `golift/unifi-poller`, `ghcr.io/onedr0p/exportarr`
- Media stack: `qmcgaw/gluetun`, `linuxserver/*` in `infra/ansible/playbooks/docker-services/templates/media-compose.yml.j2`
- CronJob: `curlimages/curl:latest` in `kubernetes/apps/observability/healthchecks-io/cronjob.yaml`
- Roles on `master`/`main`: `ansible-consul`, custom `jhughes01/*` roles, `virtUOS/ansible-loki`

## Same-major comparisons (when relevant)

Report both columns when a major jump is risky:

| Component | Why |
|---|---|
| AWS provider (5.41.0) | Latest 5.x vs 6.x |
| Consul (1.22.5) | Latest 1.22.x vs 2.0.0 |
| Kafka (3.7.0) | Latest 3.x vs 4.x |
| Terraform CLI (1.13.3) | Latest 1.13.x vs latest stable |
| Redis sidecar (7.0.6 in podinfo) | Latest 7.0.x vs current Redis major |

## Additional reference

For command snippets and API examples, see [reference.md](reference.md).
