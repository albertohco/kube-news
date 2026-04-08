## 1. Estrutura do projeto Terraform

- [x] 1.1 Criar diretório `infra/terraform/` no repositório
- [x] 1.2 Criar `infra/terraform/providers.tf` com configuração do provider `bpg/proxmox ~> 0.70` e `hashicorp/random`
- [x] 1.3 Criar `infra/terraform/variables.tf` com variáveis: `proxmox_endpoint`, `proxmox_username`, `proxmox_password`, `proxmox_node`, `vm_template`, `vm_count`, `vm_cpu`, `vm_memory`, `vm_disk_size`
- [x] 1.4 Criar `infra/terraform/terraform.tfvars.example` com valores de exemplo (sem senhas reais)
- [x] 1.5 Adicionar `infra/terraform/terraform.tfvars` e `infra/terraform/.terraform/` e `infra/terraform/*.tfstate*` ao `.gitignore`

## 2. Template cloud-init para bootstrap RKE2

- [x] 2.1 Criar `infra/terraform/cloud-init/node1.yaml.tpl` com instalação do RKE2 como servidor primário (bootstrap do cluster)
- [x] 2.2 Criar `infra/terraform/cloud-init/nodeN.yaml.tpl` com instalação do RKE2 como servidor secundário, incluindo lógica de retry para aguardar o node-1 (timeout 10 min) e join via token
- [x] 2.3 Garantir que o kubeconfig seja copiado para `~/.kube/config` do usuário padrão (`ubuntu`) no node-1

## 3. Recursos Terraform principais

- [x] 3.1 Criar `infra/terraform/main.tf` com recurso `random_password` para geração do token RKE2 (sensitive = true)
- [x] 3.2 Adicionar recurso `proxmox_virtual_environment_vm` para o `rke2-node-1` com cloud-init via `initialization` block usando `node1.yaml.tpl`
- [x] 3.3 Adicionar recursos `proxmox_virtual_environment_vm` para `rke2-node-2` e `rke2-node-3` usando `nodeN.yaml.tpl`, com `depends_on` no node-1
- [x] 3.4 Configurar cada VM com: 2 vCPU, 4096 MB RAM, disco 30 GB, rede em modo bridge (`vmbr0`), clone do template Ubuntu 22.04

## 4. Outputs

- [x] 4.1 Criar `infra/terraform/outputs.tf` com `vm_names` (lista de nomes) e `vm_ids` (lista de IDs no Proxmox)
- [x] 4.2 Garantir que o token RKE2 NÃO apareça nos outputs (`sensitive = true` e sem referência em outputs)

## 5. Validação e documentação

- [x] 5.1 Executar `terraform init` e verificar que o provider é baixado sem erros
- [x] 5.2 Executar `terraform validate` e corrigir eventuais erros de sintaxe
- [x] 5.3 Executar `terraform plan` contra o Proxmox e revisar o plano antes do apply
- [x] 5.4 Executar `terraform apply` e aguardar criação das 3 VMs
- [x] 5.5 Aguardar cloud-init concluir (~5 min) e validar cluster com `kubectl get nodes` no node-1
- [x] 5.6 Atualizar `README.md` com seção `## Infraestrutura` documentando pré-requisitos e comandos Terraform
