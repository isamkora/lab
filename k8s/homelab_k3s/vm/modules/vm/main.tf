resource "proxmox_virtual_environment_file" "cloud_init_userdata" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.node_name

  source_raw {
    data = <<-EOF
    #cloud-config
    users:
      - name: ${var.ssh_username}
        groups: sudo
        shell: /bin/bash
        sudo: ALL=(ALL) NOPASSWD:ALL
        ssh_authorized_keys:
          - ${trimspace(file(var.ssh_public_key_path))}
    packages:
      - qemu-guest-agent
    runcmd:
      - systemctl enable --now qemu-guest-agent
    EOF
    file_name = "${var.name}-userdata.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "this" {
  name      = var.name
  node_name = var.node_name
  vm_id     = var.vm_id
  pool_id   = var.pool_id
  tags      = ["k3s", "terraform", "homelab", var.role]

  agent {
    enabled = true
  }

  cpu {
    cores = local.effective_cores
  }
  memory {
    dedicated = local.effective_memory
  }

  disk {
    datastore_id = var.datastore_id
    file_id      = var.disk_file_id
    interface    = "scsi0"
    size         = local.effective_disk_size
    ssd          = true
    discard      = "on"
  }

  network_device {
    bridge = var.bridge
  }

  initialization {
    user_data_file_id = proxmox_virtual_environment_file.cloud_init_userdata.id
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  lifecycle {
    ignore_changes = [
      pool_id, # This prevents the provider from trying to manage the pool assignment
    ]
  }

  serial_device {}
}
