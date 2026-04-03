## Context

O kube-news é uma aplicação Node.js + PostgreSQL atualmente rodando via Docker Compose em ambiente local. O próximo passo é colocá-la em produção num cluster Kubernetes on-premise. O ambiente físico disponível é um host Windows com Hyper-V, que hospedará uma VM Proxmox VE. Dentro do Proxmox, serão criadas 3 VMs Ubuntu que formarão o cluster RKE2. Toda a provisão das VMs será gerenciada via Terraform.

## Goals / Non-Goals

**Goals:**
- Provisionar 3 VMs Ubuntu 22.04 no Proxmox via Terraform de forma idempotente
- Configurar RKE2 em modo HA (3 control planes + workers) via cloud-init no primeiro boot
- Estrutura Terraform parametrizável (endpoint, credenciais, recursos de CPU/RAM/disco)
- Código versionado no repositório em `infra/terraform/`

**Non-Goals:**
- Instalação manual do Proxmox VE (pré-requisito externo ao repositório)
- Deploy da aplicação kube-news no cluster (escopo de outra mudança)
- Configuração de Ingress, MetalLB, Longhorn ou cert-manager (próxima iteração)
- Ambientes multi-datacenter ou federação de clusters

## Decisions

### 1. Provider Terraform: `bpg/proxmox` em vez de `telmate/proxmox`
O provider `bpg/proxmox` tem suporte ativo, API mais moderna, suporte nativo a cloud-init via `initialization` block e melhor documentação. O `telmate/proxmox` está em modo de manutenção reduzida.

### 2. Nested Virtualization: Proxmox dentro do Hyper-V
**Alternativas consideradas:**
- VMs direto no Hyper-V via provider `taliesins/hyperv` — provider limitado, sem suporte a cloud-init nativo, difícil de manter.
- Proxmox em bare metal — ideal para produção real, mas o hardware disponível é um host Windows existente.

Proxmox dentro do Hyper-V é o melhor equilíbrio entre praticidade e funcionalidade. Requer `Set-VMProcessor -ExposeVirtualizationExtensions $true` na VM Proxmox.

### 3. Topologia RKE2: 3 nós server (control plane + worker)
**Alternativas consideradas:**
- 1 server + 2 agents: Economiza recursos, mas sem HA no control plane.
- 3 servers dedicados + agents separados: Mais robusto, mas inviável com 16 GB RAM.

Com 16 GB de RAM disponível (host Hyper-V), cada nó recebe 2 vCPU e 4 GB RAM (12 GB total), deixando ~4 GB para o SO do host e o overhead do Proxmox. Todos os nós atuam como control plane e worker simultaneamente.

### 4. Bootstrap via cloud-init em vez de Ansible
cloud-init é executado no primeiro boot sem dependência externa. O nó `node-1` inicia o cluster RKE2 (`server` sem `server:` apontando para outro), os nós `node-2` e `node-3` se unem via token compartilhado. O token é gerado aleatoriamente no Terraform e injetado via cloud-init em todos os nós.

### 5. DHCP para rede (fase inicial)
IPs estáticos serão necessários em produção real, mas para o lab inicial o DHCP simplifica o setup. A arquitetura não impede migração futura para IPs fixos via `ipconfig` no block `initialization` do Terraform.

## Risks / Trade-offs

| Risco | Mitigação |
|---|---|
| Nested virtualization tem overhead de CPU/memória | Aceitável para lab/produção leve. Para cargas intensas, migrar para bare metal. |
| RKE2 no node-2 e node-3 dependem do node-1 estar pronto | cloud-init nos nós secundários tem retry com loop de espera antes de tentar join |
| Token RKE2 em texto no state do Terraform | Usar `sensitive = true` nas variáveis e não versionar o `terraform.tfstate` (`.gitignore`) |
| 16 GB RAM é o mínimo — sem folga para picos | Monitorar com `kubectl top nodes`. Reduzir réplicas da app se necessário |
| cloud-init falha silencioso difícil de debugar | Logs em `/var/log/cloud-init-output.log` em cada VM |

## Migration Plan

1. Habilitar nested virtualization na VM Proxmox no Hyper-V:
   ```powershell
   Set-VMProcessor -VMName "proxmox" -ExposeVirtualizationExtensions $true
   ```
2. Criar e configurar VM Proxmox VE (passo manual, uma única vez)
3. Fazer upload da cloud image Ubuntu 22.04 no Proxmox
4. Configurar credenciais no arquivo `terraform.tfvars` (não versionado)
5. Executar `terraform init && terraform apply`
6. Aguardar cloud-init finalizar (~5 min) e validar cluster com `kubectl get nodes`

**Rollback:** `terraform destroy` remove todas as VMs. O Proxmox em si não é afetado.

## Open Questions

- O host Hyper-V tem acesso à internet para que as VMs baixem pacotes RKE2? (necessário no primeiro apply)
- Será usado storage externo (NFS/iSCSI) para o Longhorn, ou apenas discos locais das VMs?
