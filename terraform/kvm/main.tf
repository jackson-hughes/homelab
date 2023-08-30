terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.6.10"
    }
  }
}

provider "libvirt" {
  uri = "qemu+ssh://${var.libvirt_user}@${var.libvirt_hostname}/system?keyfile=${var.libvirt_ssh_key}&sshauth=privkey"
}

resource "libvirt_volume" "fedora35_base" {
  name   = "fedora35_base.qcow2"
  source = "https://download.fedoraproject.org/pub/fedora/linux/releases/35/Cloud/x86_64/images/Fedora-Cloud-Base-35-1.2.x86_64.qcow2"
}

resource "libvirt_volume" "fedora37_base" {
  name   = "fedora37_base.qcow2"
  source = "https://download.fedoraproject.org/pub/fedora/linux/releases/37/Cloud/x86_64/images/Fedora-Cloud-Base-37-1.7.x86_64.qcow2"
}

resource "libvirt_volume" "fedora38_base" {
  name = "fedora38_base.qcow2"
  source = "https://download.fedoraproject.org/pub/fedora/linux/releases/38/Cloud/x86_64/images/Fedora-Cloud-Base-38-1.6.x86_64.qcow2"
}

locals {
  os_base_disk = {
    fedora35 = libvirt_volume.fedora35_base.id
    fedora37 = libvirt_volume.fedora37_base.id
    fedora38 = libvirt_volume.fedora38_base.id
  }
}

resource "libvirt_volume" "main" {
  for_each       = { for vm in var.kvm_virtual_machines : vm.name => vm }
  name           = "${each.value.name}.qcow2"
  base_volume_id = local.os_base_disk[each.value.os]
  size           = each.value.disk_size
}

resource "libvirt_cloudinit_disk" "main" {
  for_each  = { for vm in var.kvm_virtual_machines : vm.name => vm }
  name      = "${each.value.name}_cloud_init.iso"
  user_data = templatefile("${path.module}/templates/cloud_init.tpl", { hostname = each.value.name })

  lifecycle {
    ignore_changes = [
      user_data
    ]
  }
}

resource "libvirt_domain" "main" {
  for_each  = { for vm in var.kvm_virtual_machines : vm.name => vm }
  name      = each.value.name
  vcpu      = each.value.cpus
  memory    = each.value.memory
  cmdline   = []
  autostart = true

  cloudinit = libvirt_cloudinit_disk.main[each.value.name].id

  cpu = {
    mode = "host-passthrough"
  }

  disk {
    volume_id = libvirt_volume.main[each.value.name].id
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }

  network_interface {
    bridge = "br0"
  }
}
