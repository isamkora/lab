variable "name" {
  type = string
}
variable "vm_id" {
  type = number
}
variable "node_name" {
  type    = string
  default = "prox"
}
variable "cores" {
  type    = number
  default = null
}
variable "memory" {
  type    = number
  default = null
}
variable "disk_size" {
  type    = number
  default = null
}
variable "role" {
  type        = string
  description = "master or worker — used for tagging"
}
variable "ssh_username" {
  type    = string
  default = "kora"
}

variable "pool_id" {
  type    = string
  default = "terraform-pool"
}

variable "template_vm_id" {
  description = "The template VM resource or ID to clone from"
  type        = any
}

variable "network_bridge" {
  type = string
  default = "vmbr0"
}

variable "datastore_vm_disks" {
  type = string
  default = "local-lvm"
}

variable "ssh_public_key_path" {
  type = string
  default = "~/.ssh/id_ed25519.pub"
}

variable "disk_interface" {
  type = string
  default = "scsi0"
}

variable "datastore_files" {
  type = string
  default = "local"
}
