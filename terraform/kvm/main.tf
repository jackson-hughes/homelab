terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.6.10"
    }
  }
}

provider "libvirt" {
  uri = "qemu+ssh://${var.libvirt_user}@${var.libvirt_hostname}/system?keyfile=${var.libvirt_ssh_key}"
}

resource "libvirt_volume" "centos8_base" {
  name   = "centos8_base.qcow2"
  source = "https://cloud.centos.org/centos/8/x86_64/images/CentOS-8-GenericCloud-8.4.2105-20210603.0.x86_64.qcow2"
}

locals {
  kvm_virtual_machines = [
    "consul01",
    "consul02",
    "consul03",
  ]
}

resource "libvirt_volume" "main" {
  count          = length(local.kvm_virtual_machines)
  name           = element(local.kvm_virtual_machines, count.index)
  base_volume_id = libvirt_volume.centos8_base.id
}

resource "libvirt_cloudinit_disk" "main" {
  count     = length(local.kvm_virtual_machines)
  name      = "${element(local.kvm_virtual_machines, count.index)}_cloud_init.iso"
  user_data = templatefile("${path.module}/templates/cloud_init.tpl", { hostname = element(local.kvm_virtual_machines, count.index) })
}


resource "libvirt_domain" "main" {
  count   = length(local.kvm_virtual_machines)
  name    = element(local.kvm_virtual_machines, count.index)
  memory  = "1024"
  vcpu    = "1"
  cmdline = []

  cloudinit = libvirt_cloudinit_disk.main[count.index].id

  disk {
    volume_id = libvirt_volume.main[count.index].id
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
