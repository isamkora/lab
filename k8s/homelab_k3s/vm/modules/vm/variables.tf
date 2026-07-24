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
variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}
variable "datastore_id" {
  type    = string
  default = "local-lvm"
}
variable "bridge" {
  type    = string
  default = "vmbr0"
}
variable "pool_id" {
  type    = string
  default = "terraform-pool"
}
variable "disk_file_id" {
  type    = string
  default = "local:iso/ubuntu-server-26.04.img"
}
