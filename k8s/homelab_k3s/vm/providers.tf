terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.110"
    }
  }
}

provider "proxmox" {
  endpoint  = local.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true # only if using self-signed certs

  ssh {
    agent    = true
    username = local.ssh_admin_username

    node {
      name    = local.proxmox_node
      address = local.proxmox_host
    }
  }
}
