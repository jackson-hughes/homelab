provider "libvirt" {
  # Ensure SSH key is added to ssh-agent
  uri = "qemu+ssh://${var.libvirt_user}@${var.libvirt_hostname}/system?sshauth=privkey&known_hosts_verify=ignore"
}
