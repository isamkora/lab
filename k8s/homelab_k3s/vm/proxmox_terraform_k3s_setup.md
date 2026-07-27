# Proxmox + Terraform Homelab Setup

Documentation of the full path from a Proxmox host to a Terraform module that clones k3s-ready VMs in seconds via linked clones.

---

## 1. Overview

This setup provisions VMs on a single-node Proxmox server for a k3s Kubernetes homelab, using:

- A **least-privilege Proxmox service account** dedicated to Terraform
- **Terraform** (via the `bpg/proxmox` provider) to define infrastructure as code
- A **Proxmox VM template** with `qemu-guest-agent` pre-installed, cloned via **linked clones** for fast VM creation
- A reusable **Terraform module** (`modules/vm/`) that provisions master/worker nodes from that template

---

## 2. Proxmox Least-Privilege Setup

Rather than using the `root` API token for Terraform, a dedicated role, user, pool, and token were created.

### 2.1 Create the role

```bash
pveum role add TerraformProv -privs "VM.Allocate VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Cloudinit VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Audit VM.PowerMgmt VM.Console VM.GuestAgent.Audit Datastore.Allocate Datastore.AllocateSpace Datastore.Audit Datastore.AllocateTemplate Pool.Allocate SDN.Use"
```

Notes on privilege choices:
- `Sys.*` privileges (node/host-level config, power, console) were **deliberately excluded** — Terraform never needs to touch the hypervisor itself, only VMs.
- `VM.Migrate` was excluded — irrelevant on a single-node cluster.
- `VM.Monitor` (used in older Proxmox versions) was **replaced by `VM.GuestAgent.Audit`** on Proxmox VE 9+, where `VM.Monitor` no longer exists.
- `Datastore.Allocate` (broader than `Datastore.AllocateSpace`) was needed specifically for uploading cloud-init snippet files.

### 2.2 Create the user

Proxmox-native account (`@pve` realm) — no shell login, exists purely as an API/automation identity:

```bash
pveum user add terraform@pve --comment "Terraform automation"
```

### 2.3 Create a resource pool

Scopes Terraform-managed VMs into one group:

```bash
pveum pool add terraform-pool --comment "VMs managed by Terraform"
```

### 2.4 Bind the role to the user at each required path

ACLs are checked per-path, not just via the role's privilege list — each of these had to be added individually after hitting permission errors during actual provisioning:

```bash
pveum aclmod /pool/terraform-pool -user terraform@pve -role TerraformProv
pveum aclmod /storage/local -user terraform@pve -role TerraformProv
pveum aclmod /storage/local-lvm -user terraform@pve -role TerraformProv
pveum aclmod /nodes/prox -user terraform@pve -role TerraformProv
pveum aclmod /sdn/zones/localnetwork/vmbr0 -user terraform@pve -role TerraformProv
pveum aclmod /vms -user terraform@pve -role TerraformProv
```

> `/vms` matters specifically for **VM creation** — pool-level ACLs only apply once a VM is already a pool member, which doesn't help during the initial create step.

### 2.5 Generate the API token

```bash
pveum user token add terraform@pve terraform-token --privsep 0
```

- `--privsep 0` means the token inherits the user's full permission set (appropriate here since the user exists solely for this token).
- The secret is shown **once** — copy it immediately.

### 2.6 Verifying the setup

```bash
pveum acl list                          # all ACL bindings
pveum role list TerraformProv           # role's privilege set
pveum user list                         # confirm user exists
pveum user permissions terraform@pve    # resolved effective permissions (most useful check)
pveum user token list terraform@pve     # confirm token exists
```

---

## 3. Secrets Handling

The API token is never committed to code.

**Declare as a sensitive variable:**
```hcl
# variable.tf
variable "proxmox_api_token" {
  type      = string
  sensitive = true
}
```

**Supply via environment variable** (not a `.tfvars` file, to avoid anything touching disk in the repo):
```bash
export TF_VAR_proxmox_api_token="terraform@pve!terraform-token=<secret>"
```

**Persisted across shell sessions** via a gitignored file sourced from the shell config:
```bash
~/.config/bash/secrets.env
```
```bash
[ -f ~/.config/bash/secrets.env ] && source ~/.config/bash/secrets.env
```

**Gitignore pattern** — a wildcard, not an exact filename match:
```
# Sensitive files
*.env
*.key
*.pem
```
(`*.env` catches `secrets.env` and similar; an exact `.env` entry would not.)

**Terraform state** (`terraform.tfstate`) also holds sensitive values in plaintext and needs the same care:
```bash
chmod 600 terraform.tfstate*
```
already covered by `terraform.tfstate*` in `.gitignore`.

---

## 4. Terraform Provider Configuration

```hcl
# providers.tf
provider "proxmox" {
  endpoint  = local.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true

  ssh {
    agent    = true
    username = local.ssh_admin_username

    node {
      name    = local.proxmox_node
      address = local.proxmox_host   # Tailscale hostname/IP
    }
  }
}
```

Two separate connections are involved:
- **API** (`endpoint`) — used for most operations, over the LAN address.
- **SSH** (`ssh` block) — required specifically for certain disk operations (e.g. custom disk creation during cloning). The `node { address = ... }` override lets SSH route over **Tailscale** independently of the API's LAN endpoint, solving a case where the LAN path was reachable for the API but not for SSH.

---

## 5. Building the VM Template

Rather than provisioning every VM from a raw cloud image (slow — full package install every time), a **template** is built once and cloned repeatedly.

### 5.1 Template resource

```hcl
# template.tf
resource "proxmox_virtual_environment_file" "template_userdata" {
  content_type = "snippets"
  datastore_id = local.datastore_files
  node_name    = local.proxmox_node

  source_raw {
    data = <<-EOF
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
  tags      = ["template", "terraform"]

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
    interface    = "scsi0"
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
    ignore_changes  = [template]
    prevent_destroy = true
  }

  serial_device {}
}
```

### 5.2 Converting to a template — correct order (learned the hard way)

Getting this sequence wrong causes cascading failures (broken boot, stale cloud-init state, unreadable disks). The **correct order**:

1. **Apply the resource as a normal, bootable VM.**
   Do **not** set `template = true` in the resource config — that converts the VM to read-only *at creation*, before it ever gets to boot and run cloud-init. Do **not** set `started = false` either — the VM needs to actually boot.

   ```bash
   terraform apply -target=proxmox_virtual_environment_vm.k3s_template
   ```

2. **Wait for the guest agent to come up** (first boot is slow — full `apt install qemu-guest-agent`):
   ```bash
   qm agent 900 ping
   qm guest exec 900 -- cloud-init status   # wait for "status: done"
   ```

3. **Clean cloud-init's state** so every future clone is treated as a genuinely new instance (otherwise cloud-init sees a matching instance-id and skips reprocessing entirely — meaning per-clone users/SSH keys never get applied):
   ```bash
   qm guest exec 900 -- cloud-init clean --logs
   qm guest exec 900 -- shutdown now
   qm status 900   # wait for "stopped"
   ```

4. **Convert to a template** (this is a manual, one-time Proxmox operation — Terraform doesn't manage this step):
   ```bash
   qm template 900
   ```
   Confirm:
   ```bash
   qm config 900 | grep template   # should show template: 1
   lvs | grep vm-900               # disk should be renamed to base-900-disk-0
   ```

5. **Protect it from Terraform re-managing/destroying it** via the `lifecycle` block already shown above:
   - `ignore_changes = [template]` — without this, any unrelated `apply` touching the resource can try to convert the template back to a regular VM (which Proxmox rejects) since Terraform's config doesn't know about the manual `qm template` step.
   - `prevent_destroy = true` — blocks any accidental destroy/recreate of the template.

### 5.3 Common pitfalls encountered

| Symptom | Cause |
|---|---|
| `Linked clone feature is not supported` | Template's `qm template` conversion never completed (disk still named `vm-900-disk-0`, not `base-900-disk-0`) |
| `Cannot convert a template back to a regular VM` | Missing `ignore_changes = [template]` — a full `apply` tried to "fix" the drift between config and the manually-applied template state |
| VM stuck restart-looping with `Nothing to boot: No such file or directory` (iPXE) | No explicit boot order — needed to ensure the disk (not network) is the boot device |
| `Cannot shrink ... it is not supported` | Disk size in config was lower than the disk's actual current size — Proxmox/QEMU disks can only grow, never shrink |
| Console always shows `ubuntu login:`, never the custom username | Stale cloud-init instance-id baked into the template's disk — cloud-init skipped reprocessing on every clone. Fixed by `cloud-init clean --logs` **before** templating |
| `qm start` fails with `Permission denied` on `base-900-disk-0` | Template disks are converted to read-only base volumes — cannot be started directly; must destroy/rebuild rather than "un-template" |

---

## 6. Terraform Module: `modules/vm/`

A single reusable module provisions any VM (master or worker) by **cloning from the template**, rather than building from a raw disk image.

### 6.1 Module resource (clone-based)

```hcl
# modules/vm/main.tf
resource "proxmox_virtual_environment_file" "cloud_init_userdata" {
  content_type = "snippets"
  datastore_id = var.datastore_id
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

  clone {
    vm_id = var.template_vm_id
    full  = false   # linked clone — fast, space-efficient
  }

  disk {
    datastore_id = var.datastore_id
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
    ignore_changes = [pool_id]
  }

  serial_device {}
}
```

Note the per-clone cloud-init snippet only contains the `users:` section — the template already has `qemu-guest-agent` installed permanently, so there's no need to reinstall it on every clone (this was previously wasting time on every apply).

### 6.2 Role-based spec defaults

```hcl
# modules/vm/locals.tf
locals {
  role_defaults = {
    master = { cores = 2, memory = 4096, disk_size = 40 }
    worker = { cores = 4, memory = 8192, disk_size = 50 }
  }
  effective_cores     = var.cores != null ? var.cores : local.role_defaults[var.role].cores
  effective_memory    = var.memory != null ? var.memory : local.role_defaults[var.role].memory
  effective_disk_size = var.disk_size != null ? var.disk_size : local.role_defaults[var.role].disk_size
}
```

Both `disk_size` variables default to `null`, which acts as a sentinel meaning "caller didn't specify — use the role's default." Both role defaults are kept comfortably above the template's own disk size (30GB), since disks can only grow, never shrink.

### 6.3 Module variables

```hcl
# modules/vm/variables.tf
variable "name"                 { type = string }
variable "vm_id"                { type = number }
variable "role" {
  type        = string
  description = "master or worker — used for tagging and spec defaults"
}
variable "template_vm_id" {
  description = "The template VM's resource ID to clone from"
  type        = any
}

variable "node_name"            { type = string; default = "prox" }
variable "bridge"                { type = string; default = "vmbr0" }
variable "datastore_id"          { type = string; default = "local-lvm" }
variable "ssh_public_key_path"   { type = string; default = "~/.ssh/id_ed25519.pub" }
variable "ssh_username"          { type = string; default = "kora" }
variable "pool_id"               { type = string; default = "terraform-pool" }

variable "cores"     { type = number; default = null }
variable "memory"    { type = number; default = null }
variable "disk_size" { type = number; default = null }
```

> Rule of thumb applied throughout: values the **caller must be able to override** are `variable`s (bridge, datastore, SSH key path, specs); values that are **fixed identity of a single resource** or **pure computation** are `local`s (role defaults, effective spec resolution); values used only **once**, with no real prospect of changing independently (e.g. `"scsi0"`), are left as plain literals rather than over-abstracted into either.

### 6.4 Calling the module (root)

```hcl
# vms.tf
module "k3s_master" {
  source              = "./modules/vm"
  name                = "k3s-master"
  vm_id               = 901
  node_name           = local.proxmox_node
  bridge              = local.network_bridge
  datastore_id        = local.datastore_vm_disks
  ssh_public_key_path = local.ssh_public_key_path
  template_vm_id      = proxmox_virtual_environment_vm.k3s_template.id
  role                = "master"
  ssh_username        = "master"
}

module "k3s_worker" {
  source              = "./modules/vm"
  count               = 2
  name                = "k3s-worker-${count.index + 1}"
  vm_id               = 902 + count.index
  node_name           = local.proxmox_node
  bridge              = local.network_bridge
  datastore_id        = local.datastore_vm_disks
  ssh_public_key_path = local.ssh_public_key_path
  template_vm_id      = proxmox_virtual_environment_vm.k3s_template.id
  role                = "worker"
  ssh_username        = "worker"
}
```

Key detail: `template_vm_id` is passed as **`proxmox_virtual_environment_vm.k3s_template.id`** — a real resource reference, not a raw number. This gives Terraform an explicit dependency edge, so it:
- Builds the template before attempting any clone, on a from-scratch `apply`.
- Refuses to destroy the template while a clone still references it.

A plain number (or a `local`) would silently lose both of these safety properties.

### 6.5 `count` vs `for_each` for workers

`count` was chosen deliberately for workers, since they're uniform (same spec across all instances):
```hcl
count = 2
name  = "k3s-worker-${count.index + 1}"
vm_id = 902 + count.index
```
`for_each` (keyed by a map) would be the better choice only if individual workers needed distinct specs/identities — not needed here.

### 6.6 The `pool_id` bug and its workaround

The `bpg/proxmox` provider has a known issue where **any** update to a VM resource re-issues an "add VM to pool" API call, which Proxmox rejects if the VM is already a pool member (`VM is already a pool member`). Fix:
```hcl
lifecycle {
  ignore_changes = [pool_id]
}
```
This excludes `pool_id` from reconciliation after initial creation, preventing the redundant re-add call on every subsequent `apply`.

---

## 7. Final Project File Structure

```
.
├── main.tf                  # (if used for any non-module root resources)
├── vms.tf                   # root — module "k3s_master" / "k3s_worker" calls
├── template.tf               # root — template VM + its cloud-init snippet
├── locals.tf                 # root — shared config values (host, node, bridge, datastores, etc.)
├── providers.tf               # provider config (endpoint, api_token, ssh block)
├── variable.tf                # root-level input vars (proxmox_api_token)
├── terraform.tfstate          # (gitignored)
├── .gitignore
│
└── modules/
    └── vm/
        ├── main.tf            # proxmox_virtual_environment_vm.this (clone-based) + its cloud-init snippet
        ├── locals.tf          # role_defaults + effective_* spec resolution
        ├── variables.tf       # name, vm_id, role, template_vm_id, node_name, bridge, datastore_id, etc.
        ├── outputs.tf         # vm_id, name
        └── versions.tf        # required_providers { proxmox = { source = "bpg/proxmox" } }
```

**Root `locals.tf`** (single source of truth for shared config):
```hcl
locals {
  proxmox_host        = "prox.<tailnet>.ts.net"
  proxmox_endpoint    = "https://${local.proxmox_host}:8006/"
  proxmox_node        = "prox"
  ssh_admin_username  = "root"
  network_bridge      = "vmbr0"
  datastore_vm_disks  = "local-lvm"
  datastore_files     = "local"
  ssh_public_key_path = "~/.ssh/id_ed25519.pub"
  template_vm_id      = 900
  template_image_file = "local:iso/ubuntu-server-26.04.img"
}
```

---

## 8. Installing k3s and Setting Up `kubectl` on the Laptop

### 8.1 Install k3s on the master VM

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=helm-controller" sh -
```

- The install script auto-elevates via `sudo` internally, so it doesn't need to be run as root directly — it just needs the running user (`master`) to have passwordless sudo, which the cloud-init snippet already grants.
- `--disable=helm-controller` also disables Traefik as a side effect, since Traefik ships as a Helm chart under the hood — expected, not a bug. The reason to disabling the helm-controller is because I be installing it via flux cd.

### 8.2 Get `kubectl` working locally on the VM

k3s writes its kubeconfig as `root:root`, unreadable by the `master` user by default:

```bash
sudo cat /etc/rancher/k3s/k3s.yaml   # works immediately with sudo
```

### 8.3 Move the kubeconfig to the Arch laptop

Steps actually used, in order:

1. **Copy the kubeconfig to the VM's home directory and fix ownership** so it can be transferred without `sudo`:
   ```bash
   sudo cp /etc/rancher/k3s/k3s.yaml ~/k3s.yaml
   sudo chown master:master ~/k3s.yaml
   ```

2. **Back up the existing local kubeconfig on the laptop first** (in case it already had other cluster contexts configured):
   ```bash
   cp ~/.kube/config ~/.kube/config.bak
   ```

3. **`scp` the VM's kubeconfig onto the laptop**, replacing the local one:
   ```bash
   scp master@<vm-ip>:k3s.yaml ~/.kube/config
   ```

4. **Edit the `server:` address inside the copied config** — by default it points at `127.0.0.1` (correct only when running `kubectl` *on* the VM itself), so it needs to be changed to the master VM's actual reachable IP:
   ```bash
   # inside ~/.kube/config
   server: https://<master-vm-ip>:6443
   ```

5. **Verify from the laptop:**
   ```bash
   kubectl get nodes
   ```

> Worth remembering for later: if a second cluster/context ever needs to coexist locally (e.g. once the kubeadm multi-node cluster is built), merging kubeconfigs (`KUBECONFIG=file1:file2 kubectl config view --flatten`) is the way to go rather than repeatedly overwriting `~/.kube/config` — the backup step above was the safe call for a first-time single-cluster setup.

---

## 9. Operational Notes

- **VM IPs without the guest agent responding:** check the DHCP lease table, the VM's MAC (`qm config <id> | grep net0`) cross-referenced against ARP, or the console MOTD — the guest agent is the most reliable path once it's up (`qm agent <id> network-get-interfaces`).
- **Kubeconfig permissions after k3s install:** `/etc/rancher/k3s/k3s.yaml` is root-owned by default. Either `sudo kubectl ...`, copy it to `~/.kube/config` with corrected ownership, or install with `--write-kubeconfig-mode=644`.
- **k3s without Helm controller:** `INSTALL_K3S_EXEC="--disable=helm-controller" sh -` (also disables Traefik, since it ships as a Helm chart under the hood).

## 10. Later Plans
- I would later create more templates for different use cases and modify my module to spin up new VMs. 
- Would look at building a complete CI/CD pipeline for my VM creations going forward with github actions or something else
- My current setup is running k3s on a single VM but later to switch to a master node with 2 worker nodes or more depending on how well my hardware allows me to.