# Talos Configuration

OS pin: [`talos-version`](talos-version)
Factory schematic: [`schematic.yaml`](schematic.yaml)

[`patches/`](patches/) are `talosctl patch mc` overlays. They are not applied automatically.

## Shared machine patches

Apply to every node. `talosctl upgrade --image` uses the installer you pass on the command line and does not write `machine.install.image`. Apply this patch as part of the upgrade (same factory image, `--mode no-reboot`) so a later reset or reinstall does not fall back to the vanilla installer and drop `i915`, `intel-ucode`, and `intel-ice-firmware`.

```bash
talosctl patch mc -n 192.168.1.25,192.168.1.26,192.168.1.27 \
  --mode no-reboot \
  --patch @infra/metal/patches/machine-install-image.yaml
```

`machine-containerd.yaml` is the other cluster-wide machine overlay.

## Node patches (`machine-helios-0N.yaml`)

Hostname, static address, install disk, and node-local kubelet mounts.

Do not `talosctl patch mc` these files onto a node that already has them. Talos strategic merge appends lists, so a second apply duplicates `kubelet.extraMounts`, `ResolverConfig` nameservers, and `LinkConfig` addresses/routes. `$patch: delete` of a key that is already gone fails (the control-plane `exclude-from-external-load-balancers` label). Talos does not support `$patch: replace`. Regenerate a full machine config from secrets + patches and `talosctl apply-config` that file.

Control-plane-only overlays (do not pass these when generating a worker): `cluster-scheduling.yaml`, `cluster-mayastor.yaml`, `cluster-controlplane-metrics.yaml`, `cluster-etcd-metrics.yaml`.

### Bootstrap a worker

`secrets.yaml` is the file from cluster creation (not in git). Boot the machine with the factory ISO for [`schematic.yaml`](schematic.yaml) + [`talos-version`](talos-version) (`factory.talos.dev/image/<schematic-id>/<talos-version>/metal-amd64.iso`) and wait for the maintenance API on its install NIC.

Copy [`patches/machine-helios-01.yaml`](patches/machine-helios-01.yaml) to `patches/machine-helios-04.yaml`. Set `HostnameConfig`, `LinkConfig` address, and `install.disk`. Drop `node.kubernetes.io/exclude-from-external-load-balancers: $patch: delete` — Talos only sets that label on control planes, and deleting a missing key fails.

```bash
TALOS_VER="$(tr -d '[:space:]' < infra/metal/talos-version)"
KUBE_VER="$(kubectl version -o json | jq -r .serverVersion.gitVersion)"

talosctl gen config helios https://kube.helios.ducknet.io:6443 \
  --with-secrets secrets.yaml \
  --talos-version "${TALOS_VER}" \
  --kubernetes-version "${KUBE_VER}" \
  --output-types worker \
  --output helios-04.yaml \
  --config-patch @infra/metal/patches/machine-install-image.yaml \
  --config-patch @infra/metal/patches/machine-containerd.yaml \
  --config-patch @infra/metal/patches/machine-helios-04.yaml

talosctl apply-config --insecure -n 192.168.1.28 --file helios-04.yaml
rm helios-04.yaml
```

Do not run `talosctl bootstrap` (that is first control plane only). The node joins via the existing API endpoint. Mayastor `DiskPool` objects and any extra `NetworkRuleConfig` source IPs are Kubernetes/control-plane follow-up, not part of this apply.
