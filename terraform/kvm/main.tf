terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.7.6"
    }
  }
}

provider "libvirt" {
  # Ensure SSH key is added to ssh-agent
  uri = "qemu+ssh://${var.libvirt_user}@${var.libvirt_hostname}/system?sshauth=privkey"
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
  name   = "fedora38_base.qcow2"
  source = "https://download.fedoraproject.org/pub/fedora/linux/releases/38/Cloud/x86_64/images/Fedora-Cloud-Base-38-1.6.x86_64.qcow2"
}

resource "libvirt_volume" "fedora40_base" {
  name   = "fedora40_base.qcow2"
  source = "https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-Generic.x86_64-40-1.14.qcow2"
}

resource "libvirt_volume" "ubuntu_24_lts_base" {
  name   = "ubuntu_24_lts_base.qcow2"
  source = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

locals {
  os_base_disk = {
    fedora35    = libvirt_volume.fedora35_base.id
    fedora37    = libvirt_volume.fedora37_base.id
    fedora38    = libvirt_volume.fedora38_base.id
    fedora40    = libvirt_volume.fedora40_base.id
    ubuntu24lts = libvirt_volume.ubuntu_24_lts_base.id
  }
}

resource "libvirt_volume" "main" {
  for_each       = { for vm in var.kvm_virtual_machines : vm.name => vm }
  name           = "${each.value.name}.qcow2"
  base_volume_id = local.os_base_disk[each.value.os]
  size           = each.value.disk_size
}

resource "libvirt_cloudinit_disk" "main" {
  for_each = {
    for vm in var.kvm_virtual_machines : vm.name => vm
    # if strcontains(vm.os, "fedora")
  }

  name      = "${each.value.name}_cloud_init.iso"
  user_data = templatefile("${path.module}/templates/cloud_init.tpl", { hostname = each.value.name })

  lifecycle {
    ignore_changes = [
      user_data
    ]
  }
}

resource "libvirt_domain" "main" {
  for_each = { for vm in var.kvm_virtual_machines : vm.name => vm }

  name      = each.value.name
  vcpu      = each.value.cpus
  memory    = each.value.memory
  autostart = true
  type      = "kvm"

  cloudinit = libvirt_cloudinit_disk.main[each.value.name].id

  cpu {
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
