# Software Version Audit — Reference

Command snippets and API patterns for this homelab repo.

## Repo grep patterns

```bash
# Broad scan for version pins
rg 'version:|tag:|image:|consul_version|kafka_version|node_exporter_version|filebeat_version' \
  infra/ansible kubernetes infra/terraform --glob '*.{yaml,yml,tf,hcl,txt,j2}'
```

## Terraform Registry (proper semver sort)

```python
import json, re, urllib.request

def latest_stable_provider(namespace, name, declared_major=None):
    url = f"https://registry.terraform.io/v1/providers/{namespace}/{name}/versions"
    data = json.load(urllib.request.urlopen(url))
    stable = sorted(
        {v["version"] for v in data["versions"] if re.fullmatch(r"\d+\.\d+\.\d+", v["version"])},
        key=lambda s: tuple(map(int, s.split("."))),
    )
    latest = stable[-1]
    same_major = None
    if declared_major is not None:
        in_major = [v for v in stable if v.startswith(f"{declared_major}.")]
        same_major = in_major[-1] if in_major else None
    return {"latest": latest, "same_major": same_major, "all_stable": stable}

# Example: latest_stable_provider("hashicorp", "aws", declared_major="5")
# → latest 6.x.x, same_major latest 5.x.x (pass major from declared pin, e.g. "5" from 5.41.0)
```

```bash
# Terraform CLI
curl -sL https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r .current_version
```

## Helm charts (Artifact Hub)

```bash
curl -sL "https://artifacthub.io/api/v1/packages/helm/jetstack/cert-manager" | jq -r .version
curl -sL "https://artifacthub.io/api/v1/packages/helm/victoriametrics/victoria-metrics-k8s-stack" | jq -r .version
```

Homepage chart (jameswynn — not generic search):

```bash
curl -sL https://jameswynn.github.io/helm-charts/index.yaml | awk '/^  homepage:/{f=1} f && /^    version:/{print; exit}'
```

## GitHub (authenticated via gh)

```bash
gh release view --repo fluxcd/flux2 --json tagName -q .tagName
gh release view --repo hashicorp/consul --json tagName -q .tagName
# Kafka has no GitHub releases; use tags. Sort semver numerically — never `head -1` (API/lex order ≠ latest).
gh api repos/apache/kafka/tags --paginate -q '.[] | select(.name | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) | .name' \
  | sort -t. -k1,1n -k2,2n -k3,3n | tail -1
gh api repos/apache/kafka/tags --paginate -q '.[] | select(.name | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) | .name' \
  | sort -t. -k1,1n -k2,2n -k3,3n | grep '^3\.' | tail -1  # latest 3.x (same-major)
gh release list --repo hashicorp/consul --limit 20 | awk '/^v1\./{print $1; exit}'  # latest 1.x
```

## PyPI & Galaxy

```bash
curl -sL https://pypi.org/pypi/ansible/json | jq -r .info.version
curl -sL "https://galaxy.ansible.com/api/v1/roles/?owner__username=geerlingguy&name=docker" \
  | jq -r '.results[0].summary_fields.versions[0].name'
```

## Forgejo (Garage)

```bash
curl -sL 'https://git.deuxfleurs.fr/api/v1/repos/Deuxfleurs/garage/releases?limit=1' | jq -r '.[0].tag_name'
```

## Flux / Kubernetes runtime

```bash
flux get helmreleases -A
flux get sources git -A
kubectl get pods -A -o custom-columns='NS:.metadata.namespace,IMAGE:.spec.containers[*].image' --no-headers | sort -u
```

## Ansible Docker hosts

```bash
docker ps --format '{{.Names}}\t{{.Image}}'
docker inspect -f '{{.Config.Image}}' prometheus
```

## Validation heuristics

| Signal | Action |
|---|---|
| `latest < declared` | Recheck source and sort logic |
| Major version jump | Confirm canonical source; add same-major column |
| Docker Hub tag looks wrong (e.g. prometheus `0.15.0`) | Switch to GitHub releases |
| GitHub 403 rate limit | Use `gh api` with auth, or wait/retry |
| Registry `.versions[-1]` ≠ expected | Re-sort — array is not semver-ordered |
| GitHub tags `head -1` or API page order | Semver-sort numerically (`sort -t. -k1,1n …`) before taking latest |
| Ansible `*_version` var | Confirm whether it's app binary, role default, or collection pin |

## HelmRelease files in this repo

| File | Chart |
|---|---|
| `kubernetes/infrastructure/controllers/cert-manager/release.yaml` | cert-manager |
| `kubernetes/infrastructure/controllers/external-secrets/release.yaml` | external-secrets |
| `kubernetes/infrastructure/config/external-dns/release.yaml` | external-dns |
| `kubernetes/infrastructure/controllers/metallb/release.yaml` | metallb |
| `kubernetes/infrastructure/controllers/openebs/release.yaml` | openebs |
| `kubernetes/infrastructure/controllers/traefik/release.yaml` | traefik |
| `kubernetes/infrastructure/controllers/victoria-metrics-operator/operator-release.yaml` | victoria-metrics-operator |
| `kubernetes/apps/observability/victoria-metrics/release.yaml` | victoria-metrics-k8s-stack |
| `kubernetes/apps/observability/prometheus-node-exporter/release.yaml` | prometheus-node-exporter |
| `kubernetes/apps/homepage/release.yaml` | homepage |
| `kubernetes/apps/podinfo/release.yaml` | podinfo |
| `kubernetes/apps/garage/release.yaml` | garage (Git chart source) |
