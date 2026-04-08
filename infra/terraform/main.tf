# Token RKE2 compartilhado entre todos os nós do cluster
resource "random_password" "rke2_token" {
  length  = 64
  special = false
}

# Busca o template Ubuntu 22.04 existente no Proxmox
data "proxmox_virtual_environment_vms" "template" {
  node_name = var.proxmox_node

  filter {
    name   = "name"
    values = [var.vm_template]
  }
}

# ─────────────────────────────────────────────
# NODE-1: Control Plane primário + Worker
# ─────────────────────────────────────────────

resource "proxmox_virtual_environment_file" "cloud_init_node1" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node

  source_raw {
    data = templatefile("${path.module}/cloud-init/node1.yaml.tpl", {
      rke2_token     = random_password.rke2_token.result
      vm_password    = var.vm_password
      ssh_public_key = var.vm_ssh_public_key
      node1_ip       = local.node1_ip
      dns_server_1   = split(" ", var.vm_dns_servers)[0]
      dns_server_2   = split(" ", var.vm_dns_servers)[1]
    })
    file_name = "rke2-node1-cloud-init.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "rke2_node1" {
  name      = "rke2-node-1"
  node_name = var.proxmox_node
  on_boot   = true

  clone {
    vm_id = data.proxmox_virtual_environment_vms.template.vms[0].vm_id
    full  = true
  }

  agent {
    enabled = true
  }

  cpu {
    cores = var.vm_cpu
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.vm_memory
  }

  disk {
    datastore_id = var.vm_datastore
    size         = var.vm_disk_size
    interface    = "scsi0"
    file_format  = "raw"
    discard      = "on"
  }

  network_device {
    bridge = var.vm_network_bridge
    model  = "virtio"
  }

  initialization {
    ip_config {
      ipv4 {
        address = var.vm_ips[0]
        gateway = var.vm_gateway
      }
    }
    dns {
      servers = split(" ", var.vm_dns_servers)
    }
    user_data_file_id = proxmox_virtual_environment_file.cloud_init_node1.id
  }

  lifecycle {
    ignore_changes = [clone]
  }
}

# Aguarda o QEMU agent do node-1 reportar o IP (necessário para nodes 2 e 3)
resource "time_sleep" "wait_for_node1" {
  depends_on      = [proxmox_virtual_environment_vm.rke2_node1]
  create_duration = "90s"
}

# IP estático do node-1 (extraído da variável CIDR, sem a máscara)
locals {
  node1_ip = split("/", var.vm_ips[0])[0]
}

# ─────────────────────────────────────────────
# NODE-2: Control Plane secundário + Worker
# ─────────────────────────────────────────────

resource "proxmox_virtual_environment_file" "cloud_init_node2" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node
  depends_on   = [time_sleep.wait_for_node1]

  source_raw {
    data = templatefile("${path.module}/cloud-init/nodeN.yaml.tpl", {
      hostname       = "rke2-node-2"
      node1_ip       = local.node1_ip
      rke2_token     = random_password.rke2_token.result
      vm_password    = var.vm_password
      ssh_public_key = var.vm_ssh_public_key
      dns_server_1   = split(" ", var.vm_dns_servers)[0]
      dns_server_2   = split(" ", var.vm_dns_servers)[1]
    })
    file_name = "rke2-node2-cloud-init.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "rke2_node2" {
  name       = "rke2-node-2"
  node_name  = var.proxmox_node
  on_boot    = true
  depends_on = [time_sleep.wait_for_node1]

  clone {
    vm_id = data.proxmox_virtual_environment_vms.template.vms[0].vm_id
    full  = true
  }

  agent {
    enabled = true
  }

  cpu {
    cores = var.vm_cpu
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.vm_memory
  }

  disk {
    datastore_id = var.vm_datastore
    size         = var.vm_disk_size
    interface    = "scsi0"
    file_format  = "raw"
    discard      = "on"
  }

  network_device {
    bridge = var.vm_network_bridge
    model  = "virtio"
  }

  initialization {
    ip_config {
      ipv4 {
        address = var.vm_ips[1]
        gateway = var.vm_gateway
      }
    }
    dns {
      servers = split(" ", var.vm_dns_servers)
    }
    user_data_file_id = proxmox_virtual_environment_file.cloud_init_node2.id
  }

  lifecycle {
    ignore_changes = [clone]
  }
}

# ─────────────────────────────────────────────
# NODE-3: Control Plane terciário + Worker
# ─────────────────────────────────────────────

resource "proxmox_virtual_environment_file" "cloud_init_node3" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node
  depends_on   = [time_sleep.wait_for_node1]

  source_raw {
    data = templatefile("${path.module}/cloud-init/nodeN.yaml.tpl", {
      hostname       = "rke2-node-3"
      node1_ip       = local.node1_ip
      rke2_token     = random_password.rke2_token.result
      vm_password    = var.vm_password
      ssh_public_key = var.vm_ssh_public_key
      dns_server_1   = split(" ", var.vm_dns_servers)[0]
      dns_server_2   = split(" ", var.vm_dns_servers)[1]
    })
    file_name = "rke2-node3-cloud-init.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "rke2_node3" {
  name       = "rke2-node-3"
  node_name  = var.proxmox_node
  on_boot    = true
  depends_on = [time_sleep.wait_for_node1]

  clone {
    vm_id = data.proxmox_virtual_environment_vms.template.vms[0].vm_id
    full  = true
  }

  agent {
    enabled = true
  }

  cpu {
    cores = var.vm_cpu
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.vm_memory
  }

  disk {
    datastore_id = var.vm_datastore
    size         = var.vm_disk_size
    interface    = "scsi0"
    file_format  = "raw"
    discard      = "on"
  }

  network_device {
    bridge = var.vm_network_bridge
    model  = "virtio"
  }

  initialization {
    ip_config {
      ipv4 {
        address = var.vm_ips[2]
        gateway = var.vm_gateway
      }
    }
    dns {
      servers = split(" ", var.vm_dns_servers)
    }
    user_data_file_id = proxmox_virtual_environment_file.cloud_init_node3.id
  }

  lifecycle {
    ignore_changes = [clone]
  }
}
