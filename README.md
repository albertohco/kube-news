# 🗞️ Kube-News

Aplicação de notícias desenvolvida em **Node.js + Express + PostgreSQL**, criada como projeto educacional para prática de containers e orquestração com Kubernetes.

---

## 📌 Sobre o Projeto

O Kube-News permite criar, visualizar e gerenciar posts de notícias via interface web. A aplicação expõe endpoints de saúde e métricas Prometheus, tornando-a ideal para aprender sobre:

- Containerização com Docker
- Orquestração com Kubernetes
- Observabilidade com Prometheus
- Boas práticas de infraestrutura como código

---

## 🛠️ Stack

| Camada | Tecnologia |
|---|---|
| Runtime | Node.js 20 (Alpine) |
| Framework | Express.js + EJS |
| Banco de dados | PostgreSQL 13 |
| ORM | Sequelize |
| Métricas | Prometheus (`prom-client`) |
| Container | Docker |
| Orquestração | Kubernetes (kind) |

---

## 📁 Estrutura do Projeto

```
kube-news/
├── src/
│   ├── server.js          # Entrada da aplicação Express
│   ├── middleware.js       # Middleware de contagem de requisições
│   ├── system-life.js      # Endpoints de health e readiness
│   ├── models/post.js      # Model Sequelize do Post
│   ├── views/              # Templates EJS
│   ├── static/             # CSS e imagens
│   ├── Dockerfile          # Build da imagem Docker
│   └── .dockerignore
├── k8s/
│   ├── deployment.yaml     # Manifesto Kubernetes completo
│   └── README.md           # Guia detalhado do manifesto K8s
├── compose.yaml            # Docker Compose para ambiente local
├── .env                    # Variáveis de ambiente (não commitar)
├── .gitignore
├── MELHORIAS.md            # Histórico de melhorias aplicadas
└── README.md
```

---

## ⚙️ Variáveis de Ambiente

| Variável | Descrição | Padrão |
|---|---|---|
| `DB_DATABASE` | Nome do banco de dados | `kubenews` |
| `DB_USERNAME` | Usuário do banco | `kubenews` |
| `DB_PASSWORD` | Senha do banco | `pg1234` |
| `DB_HOST` | Host do banco de dados | `postgre` |

---

## 🐳 Opção 1 — Rodar com Docker Compose

### Pré-requisitos

- [Docker](https://docs.docker.com/get-docker/) instalado e em execução

### Passo a passo

**1. Clone o repositório**
```bash
git clone <url-do-repositorio>
cd kube-news
```

**2. Configure as variáveis de ambiente**

O arquivo `.env` já vem com valores padrão prontos para uso local:
```env
DB_DATABASE=kubenews
DB_USERNAME=kubenews
DB_PASSWORD=pg1234
```
> Edite o `.env` se quiser usar outras credenciais.

**3. Suba os serviços**
```bash
docker compose up --build
```

**4. Acesse a aplicação**

Abra o navegador em: **http://localhost:8080**

**5. (Opcional) Rodar em background**
```bash
docker compose up --build -d
```

**6. Parar os serviços**
```bash
docker compose down
```

### Verificando o status

```bash
# Ver containers em execução
docker compose ps

# Ver logs da aplicação
docker compose logs kubenews --tail=50

# Ver logs do banco
docker compose logs postgre --tail=30
```

### Endpoints disponíveis

| Endpoint | Descrição |
|---|---|
| `GET /` | Homepage com listagem de posts |
| `GET /post` | Formulário de criação de post |
| `POST /post` | Criar novo post |
| `GET /post/:id` | Visualizar post |
| `POST /api/post` | Criar posts em lote via JSON |
| `GET /health` | Estado de saúde da aplicação |
| `GET /ready` | Estado de prontidão |
| `GET /metrics` | Métricas Prometheus |

---

## ☸️ Opção 2 — Rodar no Kubernetes Local (kind)

### Pré-requisitos

| Ferramenta | Instalação |
|---|---|
| [Docker](https://docs.docker.com/get-docker/) | Necessário para o kind |
| [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) | `go install sigs.k8s.io/kind@latest` |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | Gerenciador de cluster |

### Passo a passo

**1. Clone o repositório**
```bash
git clone <url-do-repositorio>
cd kube-news
```

**2. Crie o cluster local com kind**
```bash
kind create cluster --name desktop
```

Verifique se os nodes estão prontos:
```bash
kubectl get nodes
```
```
NAME                    STATUS   ROLES           AGE
desktop-control-plane   Ready    control-plane   ...
desktop-worker          Ready    <none>          ...
desktop-worker2         Ready    <none>          ...
```

**3. Construa a imagem Docker da aplicação**
```bash
docker compose build
```

**4. Carregue a imagem nos nodes do cluster**

> ⚠️ Etapa obrigatória para clusters kind — os nodes são containers isolados e não acessam o daemon Docker do host diretamente.

```bash
kind load docker-image kube-news-kubenews:latest --name desktop
```

**5. Aplique o manifesto no cluster**
```bash
kubectl apply -f k8s/deployment.yaml
```

Saída esperada:
```
namespace/kubenews created
secret/kubenews-secret created
statefulset.apps/postgre created
service/postgre created
deployment.apps/kubenews created
service/kubenews created
```

**6. Aguarde os pods ficarem prontos**
```bash
kubectl get pods -n kubenews --watch
```

Aguarde todos estarem `1/1 Running`:
```
NAME                        READY   STATUS    RESTARTS
kubenews-xxxxxxxxxx-xxxxx   1/1     Running   0
kubenews-xxxxxxxxxx-xxxxx   1/1     Running   0
postgre-0                   1/1     Running   0
```

**7. Acesse a aplicação via port-forward**
```bash
kubectl port-forward svc/kubenews 8080:80 -n kubenews
```

Abra o navegador em: **http://localhost:8080**

> 💡 Mantenha o terminal com o port-forward aberto enquanto usar a aplicação.

### Verificando o status

```bash
# Ver todos os recursos do namespace
kubectl get all -n kubenews

# Ver logs da aplicação
kubectl logs -l app=kubenews -n kubenews --tail=50

# Ver logs do banco
kubectl logs postgre-0 -n kubenews --tail=30

# Testar endpoints de saúde
curl http://localhost:8080/health
curl http://localhost:8080/ready

# Descrever pod para debugar problemas
kubectl describe pod <nome-do-pod> -n kubenews
```

### Atualizar a aplicação após mudanças no código

Sempre que alterar o código, repita os passos de build e carga da imagem:

```bash
# 1. Rebuild da imagem
docker compose build

# 2. Recarregar nos nodes do kind
kind load docker-image kube-news-kubenews:latest --name desktop

# 3. Reiniciar o deployment
kubectl rollout restart deployment/kubenews -n kubenews

# 4. Acompanhar o rollout
kubectl rollout status deployment/kubenews -n kubenews
```

### Remover tudo do cluster

```bash
kubectl delete namespace kubenews
```

---

## 🧩 O que está no manifesto Kubernetes (`k8s/deployment.yaml`)

| Recurso | Tipo | Descrição |
|---|---|---|
| `kubenews` | Namespace | Isolamento de todos os recursos |
| `kubenews-secret` | Secret | Credenciais do banco (base64) |
| `postgre` | StatefulSet | PostgreSQL com identidade e volume estável |
| `postgre-data` | PersistentVolumeClaim | Persistência dos dados do banco (1Gi) |
| `postgre` | Service (ClusterIP) | Acesso interno ao banco na porta 5432 |
| `kubenews` | Deployment | Aplicação Node.js com 2 réplicas |
| `kubenews` | Service (NodePort) | Exposição da app na porta 30080 |

> Para detalhes completos sobre cada recurso e as decisões de design, consulte [`k8s/README.md`](k8s/README.md).

---

## 🔍 Comparativo entre os modos

| Característica | Docker Compose | Kubernetes (kind) |
|---|---|---|
| Complexidade | ⭐ Simples | ⭐⭐⭐ Intermediário |
| Ideal para | Desenvolvimento local rápido | Testes de comportamento em K8s |
| Persistência de dados | Gerenciada pelo Compose | PersistentVolumeClaim |
| Escalabilidade | Manual | Automática via réplicas |
| Health checks | Healthcheck no Compose | Liveness + Readiness probes |
| Acesso externo | `localhost:8080` | `kubectl port-forward` |

---

## 📖 Documentação Adicional

- [`MELHORIAS.md`](MELHORIAS.md) — Histórico de melhorias no Dockerfile e Docker Compose
- [`k8s/README.md`](k8s/README.md) — Detalhamento do manifesto Kubernetes e decisões técnicas

---

## 🏗️ Infraestrutura — Cluster Kubernetes On-Premise (RKE2 + Proxmox)

Para ambientes de produção on-premise, o projeto inclui código Terraform para provisionar automaticamente um cluster RKE2 com alta disponibilidade em 3 nós Ubuntu dentro do Proxmox VE.

### Arquitetura

```
Windows + Hyper-V
    └── VM Proxmox VE (nested virtualization)
            ├── rke2-node-1  (2 vCPU / 4 GB) — control plane + worker (bootstrap)
            ├── rke2-node-2  (2 vCPU / 4 GB) — control plane + worker
            └── rke2-node-3  (2 vCPU / 4 GB) — control plane + worker
```

### Pré-requisitos

1. **Hyper-V com nested virtualization habilitado** para a VM Proxmox:
   ```powershell
   Set-VMProcessor -VMName "proxmox" -ExposeVirtualizationExtensions $true
   ```
2. **Proxmox VE** instalado e acessível via rede
3. **Template Ubuntu 22.04 cloud image** disponível no Proxmox (nome padrão: `ubuntu-22.04-cloud`)
4. **Terraform CLI** ≥ 1.6.0 instalado na máquina que executará os comandos
5. Acesso à internet nas VMs para download do RKE2

### Como usar

```bash
cd infra/terraform

# 1. Configure suas credenciais
cp terraform.tfvars.example terraform.tfvars
# Edite terraform.tfvars com seu endpoint Proxmox, credenciais e chave SSH

# 2. Inicialize os providers
terraform init

# 3. Revise o plano
terraform plan

# 4. Provisione as 3 VMs (aguarda ~2 min para criação + 5 min para cloud-init)
terraform apply

# 5. Valide o cluster (acesse node-1 via SSH)
ssh ubuntu@$(terraform output -raw node1_ip)
kubectl get nodes
```

### Saída esperada após provisionamento

```
NAME          STATUS   ROLES                       AGE
rke2-node-1   Ready    control-plane,etcd,master   5m
rke2-node-2   Ready    control-plane,etcd,master   3m
rke2-node-3   Ready    control-plane,etcd,master   3m
```

### Variáveis principais

| Variável | Descrição | Padrão |
|---|---|---|
| `proxmox_endpoint` | URL da API Proxmox | — (obrigatório) |
| `proxmox_username` | Usuário Proxmox | `root@pam` |
| `proxmox_password` | Senha Proxmox | — (obrigatório) |
| `proxmox_node` | Nome do nó Proxmox | `pve` |
| `vm_template` | Template Ubuntu 22.04 | `ubuntu-22.04-cloud` |
| `vm_cpu` | vCPUs por VM | `2` |
| `vm_memory` | RAM em MB por VM | `4096` |
| `vm_disk_size` | Disco em GB por VM | `30` |
| `vm_ssh_public_key` | Chave pública SSH | — (obrigatório) |

### Destruir o ambiente

```bash
terraform destroy
```

> ℹ️ Para mais detalhes sobre as decisões técnicas, consulte [`openspec/changes/terraform-proxmox-rke2-cluster/design.md`](openspec/changes/terraform-proxmox-rke2-cluster/design.md).
