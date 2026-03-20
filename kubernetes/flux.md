# Flux Structure

This repo uses a 3-tier Flux layout for the Helios cluster:

- `clusters/homelab`: Flux `Kustomization` objects only.
- `infrastructure/controllers`: operators, controllers, namespaces, Helm repositories, and Helm releases.
- `infrastructure/config`: custom resources and config that depend on those controllers being present.
- `workloads`: applications and workload-specific resources that depend on infrastructure being ready.

Reconcile order:

1. `infra-controllers`
2. `infra-config`
3. `workloads`

Placement rules:

- Put a resource in `infrastructure/controllers` if it installs or runs a controller.
- Put a resource in `infrastructure/config` if it is a CR, shared secret source, or controller-owned config.
- Put a resource in `workloads` if it is an app or a workload-specific dependency.

Examples:

- `HelmRelease`, `HelmRepository`, controller namespace: `infrastructure/controllers`
- `ClusterSecretStore`, `ClusterIssuer`, `DiskPool`, `IPAddressPool`, `Certificate`: `infrastructure/config`
- `HTTPRoute`, app HelmRelease, VictoriaMetrics and VictoriaLogs workload resources: `workloads`

Guidelines:

- Prefer adding files to an existing tier over creating new top-level Flux dependencies.
- Split controllers from their dependent CRs instead of creating one mixed bundle.
- Only add a new Flux `dependsOn` edge when a real readiness boundary exists.
