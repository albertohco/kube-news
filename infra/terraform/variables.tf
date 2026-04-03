variable "proxmox_endpoint" {
  description = "URL da API do Proxmox VE (ex: https://192.168.1.100:8006)"
  type        = string
}

variable "proxmox_api_token" {
  description = "API token do Proxmox no formato user@realm!token-name=token-value"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Ignorar verificação de certificado TLS (útil em labs com certificado auto-assinado)"
  type        = bool
  default     = true
}

variable "proxmox_node" {
  description = "Nome do nó Proxmox onde as VMs serão criadas (ex: pve)"
  type        = string
  default     = "pve"
}

variable "vm_template" {
  description = "Nome do template Ubuntu 22.04 (cloud image) disponível no Proxmox"
  type        = string
  default     = "ubuntu-22.04-cloud"
}

variable "vm_cpu" {
  description = "Número de vCPUs por VM"
  type        = number
  default     = 2
}

variable "vm_memory" {
  description = "Memória RAM em MB por VM"
  type        = number
  default     = 4096
}

variable "vm_disk_size" {
  description = "Tamanho do disco em GB por VM"
  type        = number
  default     = 30
}

variable "vm_datastore" {
  description = "Datastore do Proxmox para os discos das VMs"
  type        = string
  default     = "local-lvm"
}

variable "vm_network_bridge" {
  description = "Bridge de rede do Proxmox"
  type        = string
  default     = "vmbr0"
}

variable "vm_ssh_public_key" {
  description = "Chave pública SSH para acesso às VMs (conteúdo do arquivo .pub)"
  type        = string
}
