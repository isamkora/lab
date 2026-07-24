terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.110"
    }
  }
}

provider "proxmox" {
  endpoint  = "https://prox.corvus-alnitak.ts.net:8006/"
  api_token = var.proxmox_api_token
  insecure  = true # only if using self-signed certs

  ssh {
    agent    = true
    username = "root"

    node {
      name    = "prox"
      address = "prox.corvus-alnitak.ts.net"
    }
  }
}
