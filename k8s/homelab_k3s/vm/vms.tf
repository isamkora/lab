module "k3s_master" {
  source         = "./modules/vm"
  name           = "k3s-master"
  vm_id          = 901
  template_vm_id = proxmox_virtual_environment_vm.k3s_template.id
  role           = "master"
  ssh_username   = "master"
  # disk_size      = 50
}

# module "k3s_worker" {
#   source         = "./modules/vm"
#   count          = 1
#   name           = "k3s-worker-${count.index + 1}"
#   vm_id          = 902 + count.index
#   template_vm_id = proxmox_virtual_environment_vm.k3s_template.id
#   role           = "worker"
#   ssh_username   = "worker"
# }
