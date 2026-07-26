# modules/vm/main.tf
locals {
  role_defaults = {
    master = { cores = 2, memory = 4096, disk_size = 40 }
    worker = { cores = 4, memory = 8192, disk_size = 50 }
  }
  effective_cores     = var.cores != null ? var.cores : local.role_defaults[var.role].cores
  effective_memory    = var.memory != null ? var.memory : local.role_defaults[var.role].memory
  effective_disk_size = var.disk_size != null ? var.disk_size : local.role_defaults[var.role].disk_size

}
