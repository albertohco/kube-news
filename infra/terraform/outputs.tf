output "vm_names" {
  description = "Nomes das VMs criadas no Proxmox"
  value = [
    proxmox_virtual_environment_vm.rke2_node1.name,
    proxmox_virtual_environment_vm.rke2_node2.name,
    proxmox_virtual_environment_vm.rke2_node3.name,
  ]
}

output "vm_ids" {
  description = "IDs das VMs no Proxmox"
  value = [
    proxmox_virtual_environment_vm.rke2_node1.vm_id,
    proxmox_virtual_environment_vm.rke2_node2.vm_id,
    proxmox_virtual_environment_vm.rke2_node3.vm_id,
  ]
}

output "node1_ip" {
  description = "IP do node-1 (control plane primário) — use para acesso SSH e kubectl"
  value       = local.node1_ip
}
