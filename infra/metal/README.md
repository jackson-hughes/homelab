# Talos Configuration

Managed by [TOPF](https://postfinance.github.io/topf/main/)

TOPF does not read `~/.talos/config`; it builds client certs from the secrets bundle

## Apply

```bash
topf apply --topfconfig infra/metal/topf.yaml --dry-run --mode no-reboot
topf apply --topfconfig infra/metal/topf.yaml --mode no-reboot --nodes-filter '^helios-01$'
```

Leave `--confirm` on. Never `talosctl patch mc` or `talosctl apply-config` outside TOPF.

After `topf upgrade`, run `topf apply` to persist `machine.install.image`.

## Kubernetes upgrades

`topf apply` will rewrite apiserver, controller-manager, scheduler, and kubelet image pins to `kubernetesVersion`. It does not run `upgrade-k8s` skew checks.

1. `talosctl upgrade-k8s --to X`
2. Set `kubernetesVersion: X` in `topf.yaml`
3. `topf apply --dry-run` must show no changes
4. Commit

A stale pin makes the next apply revert control-plane images.

## Add a worker

Boot the machine with the factory ISO for [`schematic.yaml`](schematic.yaml) + `talosVersion` (`factory.talos.dev/image/<schematic-id>/<talos-version>/metal-amd64.iso`) and wait for the maintenance API on its install NIC.

1. Add the node to `topf.yaml` (`role: worker`)
2. Add `node/helios-04/01-install.yaml` with that node’s `machine.install.disk`
3. If the NIC is not `enp110s0`, add a `node/helios-04/` `LinkConfig` override
4. Apply only that node:

```bash
topf apply --topfconfig infra/metal/topf.yaml --nodes-filter '^helios-04$'
```

Do not use `talosctl gen config`. Do not run `talosctl bootstrap` (first control plane only). The node joins via the existing API endpoint. Mayastor `DiskPool` objects and extra `NetworkRuleConfig` source IPs are Kubernetes/control-plane follow-up, not part of this apply.

