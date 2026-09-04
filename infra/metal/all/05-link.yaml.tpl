---
# Explicit LinkConfig disables the default DHCP-on-all-links behavior.
# Omitting destination creates a default route for the gateway's address family.
# A node with a different NIC needs a node/<host>/ override, not a change here.
apiVersion: v1alpha1
kind: LinkConfig
name: enp110s0
addresses:
  - address: {{ .Node.IP }}/24
routes:
  - gateway: 192.168.1.1
