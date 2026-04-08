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

variable "vm_gateway" {
  description = "Gateway da rede das VMs"
  type        = string
}

variable "vm_dns_servers" {
  description = "Servidores DNS separados por espaço"
  type        = string
}

variable "vm_ips" {
  description = "Lista de IPs estáticos em CIDR para as 3 VMs (node1, node2, node3)"
  type        = list(string)
}

variable "proxmox_ssh_username" {
  description = "Usuário SSH para acesso ao Proxmox (normalmente root)"
  type        = string
  default     = "root"
}

variable "proxmox_ssh_private_key_file" {
  description = "Caminho para a chave privada SSH usada para acessar o Proxmox"
  type        = string
  default     = "~/.ssh/id_rsa"
}


variable "vm_password" {
  description = "Senha do usuário ubuntu nas VMs (para acesso via console)"
  type        = string
  sensitive   = true
}

variable "vm_ssh_public_key" {
  description = "Chave pública SSH para acesso às VMs (conteúdo do arquivo .pub)"
  type        = string
}
