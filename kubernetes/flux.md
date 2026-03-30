# Flux Structure

This repo uses a 3-tier Flux layout for the Helios cluster:

- `clusters/homelab`: Flux `Kustomization` objects only
- `infrastructure/controllers`: operators, controllers, namespaces, Helm repositories, Helm releases
- `infrastructure/config`: CRs and config that depend on those controllers
- `apps`: apps and workload-specific resources

Reconcile order:

1. `infra-controllers`
2. `infra-config`
3. `apps`

Placement rules:

- Put controller installs in `infrastructure/controllers`
- Put controller config in `infrastructure/controllers` when it is required for that platform capability to become usable
- Put CRs, shared secret sources, and controller-owned config in `infrastructure/config` when they depend on an already-usable controller
- Put apps and workload-specific dependencies in `apps`

Examples:

- MetalLB `IPAddressPool` and `L2Advertisement`: `infrastructure/controllers`
- `ClusterSecretStore`, `ClusterIssuer`, `Certificate`, `DiskPool`: `infrastructure/config`
