# Flux Structure

This repo uses a 3-tier Flux layout for the Helios cluster:

- `clusters/homelab`: Flux `Kustomization` objects only
- `clusters/homelab/flux-system`: flux-operator HelmRelease and FluxInstance
- `infrastructure/controllers`: operators, controllers, namespaces, Helm repositories, Helm releases
- `infrastructure/config`: CRs and config that depend on those controllers, and controllers that need `ExternalSecret`s
- `apps`: apps and workload-specific resources

Reconcile order:

1. `infra-controllers`
2. `infra-config`
3. `apps`

## How Flux installs itself

`clusters/homelab/flux-system` holds the flux-operator HelmRelease and the FluxInstance. `infrastructure/controllers` is everything Flux installs after that.

Placement rules:

- Put controller installs in `infrastructure/controllers`
- Put CRDs and plain manifests in `infrastructure/controllers` when a controller there needs them to become usable
- Put CRs, shared secret sources, and controller-owned config in `infrastructure/config` when they depend on an already-usable controller
- Put a controller in `infrastructure/config` if it cannot become Ready without an `ExternalSecret`: `infra-controllers` waits for health, and `ClusterSecretStore` only exists after it
- Never put a CR in the same tier as the HelmRelease that installs its CRD: the server-side dry-run fails on a fresh cluster
- Put apps and workload-specific dependencies in `apps`

Examples:

- MetalLB `IPAddressPool` and `L2Advertisement`: `infrastructure/config`
- Gateway API CRDs: `infrastructure/controllers` (required for Traefik's Gateway API provider)
- `ClusterSecretStore`, `ClusterIssuer`, `Certificate`, `DiskPool`: `infrastructure/config`
- external-dns, Velero: `infrastructure/config` (pods need 1Password-backed Secrets)
