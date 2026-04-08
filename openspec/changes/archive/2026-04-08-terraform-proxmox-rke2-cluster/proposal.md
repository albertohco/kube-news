## Why

O projeto kube-news está pronto para produção no lado da aplicação, mas ainda não existe infraestrutura para hospedá-lo. É necessário provisionar um cluster Kubernetes on-premise com alta disponibilidade para receber a aplicação em produção, de forma automatizada e reproduzível.

## What Changes

- Criação do diretório `infra/terraform/` com código Terraform para provisionar VMs no Proxmox
- Configuração do provider `bpg/proxmox` para gerenciar VMs via API do Proxmox VE
- Template cloud-init que instala e configura o RKE2 automaticamente em cada nó
- 3 VMs Ubuntu 22.04 (2 vCPU / 4 GB RAM cada) formando um cluster RKE2 em HA
- Arquivo `variables.tf` com parâmetros configuráveis (endpoint Proxmox, credenciais, recursos)
- Arquivo `outputs.tf` expondo IPs e status dos nós criados

## Capabilities

### New Capabilities

- `proxmox-vm-provisioning`: Código Terraform com provider `bpg/proxmox` para criar e gerenciar as 3 VMs Ubuntu no Proxmox VE via nested virtualization no Hyper-V
- `rke2-cluster-bootstrap`: Template cloud-init que instala automaticamente o RKE2 em modo servidor HA nos 3 nós ao primeiro boot

### Modified Capabilities

## Impact

- Novo diretório `infra/terraform/` adicionado ao repositório
- Nenhum código existente da aplicação é modificado
- Requer Proxmox VE instalado em VM no Hyper-V com nested virtualization habilitado
- Requer imagem base Ubuntu 22.04 (cloud image) disponível no Proxmox
- Dependências novas: Terraform CLI, provider `bpg/proxmox ~> 0.70`
