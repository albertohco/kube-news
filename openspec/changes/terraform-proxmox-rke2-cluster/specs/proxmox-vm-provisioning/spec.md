## ADDED Requirements

### Requirement: Terraform provisiona VMs no Proxmox via API
O sistema SHALL utilizar o provider `bpg/proxmox` (versão `~> 0.70`) para criar e gerenciar VMs no Proxmox VE via API REST, de forma idempotente.

#### Scenario: Criação das 3 VMs com terraform apply
- **WHEN** o usuário executa `terraform apply` com variáveis válidas configuradas
- **THEN** o Terraform cria exatamente 3 VMs no Proxmox com os recursos especificados (2 vCPU, 4 GB RAM, 30 GB disco)

#### Scenario: Idempotência no segundo apply
- **WHEN** o usuário executa `terraform apply` novamente sem alterações
- **THEN** o Terraform não faz nenhuma modificação nas VMs existentes (0 changes)

### Requirement: VMs utilizam Ubuntu 22.04 cloud image como base
O sistema SHALL criar VMs clonando um template Ubuntu 22.04 (cloud image) previamente disponível no Proxmox. O nome do template SHALL ser configurável via variável `vm_template`.

#### Scenario: Clone do template com sucesso
- **WHEN** o template informado em `vm_template` existe no Proxmox
- **THEN** cada VM é criada como clone completo do template

#### Scenario: Template inexistente
- **WHEN** o template informado em `vm_template` não existe no Proxmox
- **THEN** o Terraform falha com mensagem de erro clara indicando o template ausente

### Requirement: Credenciais e configurações via variáveis parametrizáveis
O sistema SHALL expor todas as configurações sensíveis e de ambiente como variáveis Terraform, sem valores hardcoded nos arquivos `.tf`. As variáveis obrigatórias são: `proxmox_endpoint`, `proxmox_username`, `proxmox_password`, `proxmox_node`.

#### Scenario: Execução com terraform.tfvars
- **WHEN** o usuário cria um arquivo `terraform.tfvars` com todas as variáveis obrigatórias
- **THEN** o `terraform plan` e `terraform apply` executam sem solicitar valores interativos

#### Scenario: Arquivo terraform.tfvars não versionado
- **WHEN** o repositório é inspecionado
- **THEN** `terraform.tfvars` e `terraform.tfstate` NÃO aparecem no controle de versão (presentes no `.gitignore`)

### Requirement: Outputs expõem informações dos nós criados
O sistema SHALL gerar outputs com os nomes e IPs (quando disponíveis via DHCP) das VMs criadas, para facilitar acesso pós-provisão.

#### Scenario: Outputs após apply bem-sucedido
- **WHEN** o `terraform apply` conclui com sucesso
- **THEN** o output `vm_names` lista os nomes das 3 VMs e `vm_ids` lista seus IDs no Proxmox
