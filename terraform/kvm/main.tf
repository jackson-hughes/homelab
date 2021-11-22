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

resource "libvirt_volume" "fedora35_base" {
  name   = "fedora35_base.qcow2"
  source = "https://download.fedoraproject.org/pub/fedora/linux/releases/35/Cloud/x86_64/images/Fedora-Cloud-Base-35-1.2.x86_64.qcow2"
}

resource "libvirt_volume" "main" {
  for_each       = { for vm in var.kvm_virtual_machines : vm.name => vm }
  name           = "${each.value.name}.qcow2"
  base_volume_id = libvirt_volume.fedora35_base.id
  size           = each.value.disk_size
}

resource "libvirt_cloudinit_disk" "main" {
  for_each  = { for vm in var.kvm_virtual_machines : vm.name => vm }
  name      = "${each.value.name}_cloud_init.iso"
  user_data = templatefile("${path.module}/templates/cloud_init.tpl", { hostname = each.value.name })
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
