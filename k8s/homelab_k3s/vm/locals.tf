locals {
  proxmox_host        = "prox.corvus-alnitak.ts.net"
  proxmox_endpoint    = "https://${local.proxmox_host}:8006/"
  proxmox_node        = "prox"
  ssh_admin_username  = "root"
  network_bridge      = "vmbr0"
  datastore_vm_disks  = "local-lvm"
  datastore_files     = "local"
  ssh_public_key_path = "~/.ssh/id_ed25519.pub"
  template_vm_id      = 900
  template_image_file = "local:iso/ubuntu-server-26.04.img"
  disk_interface      = "scsi0"
}
