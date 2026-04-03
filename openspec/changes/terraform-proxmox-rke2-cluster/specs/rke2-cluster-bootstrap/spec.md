## ADDED Requirements

### Requirement: cloud-init instala RKE2 automaticamente no primeiro boot
O sistema SHALL injetar um template cloud-init em cada VM via Terraform que instale e inicie o RKE2 automaticamente no primeiro boot, sem intervenção manual.

#### Scenario: Primeiro boot do node-1 (bootstrap)
- **WHEN** a VM `rke2-node-1` inicializa pela primeira vez
- **THEN** o cloud-init instala o RKE2 como servidor primário e inicia o cluster

#### Scenario: Primeiro boot dos nodes 2 e 3 (join)
- **WHEN** as VMs `rke2-node-2` e `rke2-node-3` inicializam pela primeira vez
- **THEN** o cloud-init instala o RKE2 e une os nós ao cluster usando o IP do node-1 e o token compartilhado

### Requirement: Token RKE2 compartilhado gerado pelo Terraform
O sistema SHALL gerar um token aleatório via `random_password` do Terraform e injetá-lo via cloud-init em todos os 3 nós. O token SHALL ser marcado como `sensitive = true`.

#### Scenario: Token consistente entre os nós
- **WHEN** o `terraform apply` provisiona os 3 nós
- **THEN** todos os 3 nós recebem o mesmo valor de token RKE2 no cloud-init

#### Scenario: Token não exposto em outputs
- **WHEN** o usuário executa `terraform output`
- **THEN** o token RKE2 não aparece em texto puro no terminal

### Requirement: node-2 e node-3 aguardam o node-1 estar pronto antes do join
O cloud-init dos nós secundários SHALL incluir lógica de retry para aguardar o endpoint RKE2 do node-1 estar acessível antes de tentar ingressar no cluster.

#### Scenario: Retry bem-sucedido após node-1 inicializar
- **WHEN** o node-2 tenta join e o node-1 ainda não está pronto
- **THEN** o script aguarda (com sleep entre tentativas) e tenta novamente até sucesso ou timeout de 10 minutos

#### Scenario: Timeout de join
- **WHEN** o node-1 não fica acessível após 10 minutos
- **THEN** o cloud-init registra o erro em `/var/log/cloud-init-output.log` e falha com exit code não-zero

### Requirement: Kubeconfig acessível no node-1 após bootstrap
O sistema SHALL garantir que o kubeconfig do cluster RKE2 esteja disponível em `/etc/rancher/rke2/rke2.yaml` no node-1 após o bootstrap, com permissões ajustadas para o usuário padrão.

#### Scenario: Acesso ao cluster via kubectl no node-1
- **WHEN** o usuário acessa o node-1 via SSH após o cloud-init concluir
- **THEN** `kubectl get nodes` retorna os 3 nós com status `Ready`
