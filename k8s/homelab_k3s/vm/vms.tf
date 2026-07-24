module "k3s_master" {
  source       = "./modules/vm"
  name         = "k3s-master"
  vm_id        = 900
  role         = "master"
  ssh_username = "master"
  disk_size    = 40
}

# module "k3s_worker" {
#   source       = "./modules/vm"
#   count        = 1
#   name         = "k3s-worker-${count.index + 1}"
#   vm_id        = 901 + count.index
#   role         = "worker"
#   ssh_username = "worker"
# }
