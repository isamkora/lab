resource "proxmox_virtual_environment_file" "template_userdata" {
  content_type = "snippets"
  datastore_id = local.datastore_files
  node_name    = local.proxmox_node

  source_raw {
    data      = <<-EOF
    #cloud-config
    packages:
      - qemu-guest-agent
    runcmd:
      - systemctl enable --now qemu-guest-agent
    EOF
    file_name = "k3s-template-userdata.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "k3s_template" {
  name      = "k3s-template"
  node_name = local.proxmox_node
  vm_id     = local.template_vm_id
  # template  = true
  tags       = ["template", "terraform"]
  boot_order = [local.disk_interface]

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
    datastore_id = local.datastore_vm_disks
    file_id      = local.template_image_file
    interface    = local.disk_interface
    size         = 30
    ssd          = true
    discard      = "on"
  }

  network_device {
    bridge = local.network_bridge
  }

  initialization {
    user_data_file_id = proxmox_virtual_environment_file.template_userdata.id
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template, # ✅ Prevents Terraform from re-importing the disk
    ]
    prevent_destroy = true
  }

  serial_device {}

  # Stop the VM once it's provisioned — templates should be stopped, not running
  # started = false
}
