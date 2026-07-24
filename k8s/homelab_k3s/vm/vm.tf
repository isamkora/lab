resource "proxmox_virtual_environment_vm" "k3s_single" {
  name      = "k3s-single"
  node_name = "prox"
  vm_id     = 900
  pool_id   = "terraform-pool"
  tags      = ["k3s", "homelab", "tf"]

  agent {
    enabled = true
  }

  cpu {
    cores = 2
  }
  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = "local-lvm"
    file_id      = "local:iso/ubuntu-server-26.04.img"
    interface    = "scsi0"
    size         = 50
    ssd          = true
    discard      = "on"
  }

  network_device {
    bridge = "vmbr0"
  }

  initialization {
    user_data_file_id = proxmox_virtual_environment_file.cloud_init_userdata.id
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  serial_device {}
}

resource "proxmox_virtual_environment_file" "cloud_init_userdata" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "prox"

  source_raw {
    data      = <<-EOF
    #cloud-config
    users:
      - name: kora
        groups: sudo
        shell: /bin/bash
        sudo: ALL=(ALL) NOPASSWD:ALL
        ssh_authorized_keys:
          - ${trimspace(file("~/.ssh/id_ed25519.pub"))}
    packages:
      - qemu-guest-agent
    runcmd:
      - systemctl enable --now qemu-guest-agent
    EOF
    file_name = "k3s-single-userdata.yaml"
  }
}
