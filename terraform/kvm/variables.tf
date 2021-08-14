variable "libvirt_hostname" {
  type        = string
  description = "DNS resolvable hostname of a libvirt host"
  default     = "hv1"
}

variable "libvirt_user" {
  type        = string
  description = "user to connect to libvirt as"
  default     = "jhughes"
}

variable "libvirt_ssh_key" {
  type        = string
  description = "SSH key for libvirt connections"
  default     = "$HOME/.ssh/hv1.pem"
}

variable "kvm_virtual_machines" {
  type        = list(string) # todo: turn into a map including VM spec, e.g. CPU, etc.
  description = "List of hostnames for VMs"
  default     = []
}
