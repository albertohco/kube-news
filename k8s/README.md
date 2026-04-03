# ☸️ Kubernetes — Guia do Manifesto e Cluster Local

Documentação das melhorias aplicadas no manifesto `k8s/deployment.yaml` e instruções completas para rodar a aplicação **Kube-News** em um cluster Kubernetes local com **kind**.

---

## 📋 Pré-requisitos

| Ferramenta | Finalidade | Instalação |
|---|---|---|
| [Docker](https://docs.docker.com/get-docker/) | Build da imagem e runtime do kind | `apt install docker.io` |
| [kind](https://kind.sigs.k8s.io/) | Cluster Kubernetes local via Docker | `go install sigs.k8s.io/kind@latest` |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | CLI para interagir com o cluster | `apt install kubectl` |

---

## 🏗️ Arquitetura no Cluster

```
Namespace: kubenews
│
├── Secret: kubenews-secret
│     └── DB_DATABASE / DB_USERNAME / DB_PASSWORD
│
├── StatefulSet: postgre (1 réplica)
│     ├── Image: postgres:13.13
│     ├── PersistentVolumeClaim: postgre-data (1Gi)
│     └── Service: postgre (ClusterIP :5432)
│
└── Deployment: kubenews (2 réplicas)
      ├── Image: kube-news-kubenews:latest
      ├── Probes: /health (liveness) + /ready (readiness)
      └── Service: kubenews (NodePort 80 → 8080, porta externa 30080)
```

---

## 🔄 Melhorias Aplicadas no Manifesto

### 1. Namespace dedicado

**Antes:** todos os recursos no namespace `default`

**Depois:**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: kubenews
```

**Por quê:** Isola os recursos da aplicação dos demais workloads do cluster. Facilita o gerenciamento, aplicação de políticas e remoção completa (`kubectl delete namespace kubenews`).

---

### 2. Secret para credenciais

**Antes:** senhas em texto puro no YAML
```yaml
env:
  - name: POSTGRES_PASSWORD
    value: pg1234   # ❌ exposto
```

**Depois:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: kubenews-secret
  namespace: kubenews
type: Opaque
stringData:
  DB_DATABASE: kubenews
  DB_USERNAME: kubenews
  DB_PASSWORD: pg1234
```

```yaml
env:
  - name: POSTGRES_PASSWORD
    valueFrom:
      secretKeyRef:
        name: kubenews-secret
        key: DB_PASSWORD   # ✅ referência ao Secret
```

**Por quê:** Secrets são armazenados separadamente no etcd, podem ter RBAC próprio e nunca ficam visíveis em logs ou listagens de pods.

---

### 3. StatefulSet + PersistentVolumeClaim para o PostgreSQL

**Antes:** PostgreSQL como `Deployment` sem volume
```yaml
kind: Deployment   # ❌ sem persistência
```

**Depois:**
```yaml
kind: StatefulSet
...
volumeMounts:
  - name: postgre-data
    mountPath: /var/lib/postgresql/data
volumeClaimTemplates:
  - metadata:
      name: postgre-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 1Gi
```

**Por quê:**
- `StatefulSet` garante identidade estável ao pod do banco (nome fixo `postgre-0`)
- O `PersistentVolumeClaim` mantém os dados mesmo após restart ou recriação do pod
- `Deployment` para banco de dados causa perda total de dados ao reiniciar

---

### 4. Liveness e Readiness Probes

**Antes:** sem probes — Kubernetes não sabia se a aplicação estava saudável

**Depois (aplicação):**
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 20
  periodSeconds: 10
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 5
```

**Depois (postgres):**
```yaml
livenessProbe:
  exec:
    command: ["pg_isready", "-U", "kubenews", "-d", "kubenews"]
  initialDelaySeconds: 15
  periodSeconds: 10
readinessProbe:
  exec:
    command: ["pg_isready", "-U", "kubenews", "-d", "kubenews"]
  initialDelaySeconds: 5
  periodSeconds: 5
```

**Por quê:**
- **Liveness:** reinicia o pod automaticamente se a aplicação travar
- **Readiness:** remove o pod do balanceamento de carga enquanto não estiver pronto para receber tráfego
- `initialDelaySeconds` evita falsos positivos durante a inicialização

---

### 5. Resource Requests e Limits

**Antes:** sem limites — pods podiam consumir CPU/memória ilimitada

**Depois:**
```yaml
# Aplicação
resources:
  requests:
    cpu: "100m"      # reserva mínima garantida
    memory: "128Mi"
  limits:
    cpu: "300m"      # teto máximo permitido
    memory: "256Mi"

# PostgreSQL
resources:
  requests:
    cpu: "250m"
    memory: "256Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"
```

**Por quê:** Sem limites, um pod pode consumir todos os recursos do node e derrubar outros workloads. O scheduler também usa `requests` para decidir em qual node alocar o pod.

---

### 6. NodePort em vez de LoadBalancer

**Antes:**
```yaml
type: LoadBalancer   # ❌ fica em <pending> em cluster local
```

**Depois:**
```yaml
type: NodePort
ports:
  - port: 80
    targetPort: 8080
    nodePort: 30080   # porta acessível nos nodes
```

**Por quê:** `LoadBalancer` em cluster local sem MetalLB fica indefinidamente em `EXTERNAL-IP: <pending>`. `NodePort` expõe a porta diretamente nos nodes, permitindo acesso via `kubectl port-forward`.

---

### 7. Réplicas ajustadas para ambiente local

**Antes:** `replicas: 10` — consumo excessivo de recursos locais

**Depois:** `replicas: 2` — suficiente para testar balanceamento sem sobrecarregar o cluster

---

### 8. Imagem local com `imagePullPolicy: Never`

**Antes:** `image: fabricioveronez/kube-news:v2` — imagem inexistente no Docker Hub

**Depois:**
```yaml
image: kube-news-kubenews:latest
imagePullPolicy: Never
```

**Por quê:** Em cluster kind, os nodes são containers Docker isolados. A flag `Never` instrui o kubelet a usar apenas imagens já presentes localmente, sem tentar fazer pull do registry.

---

## 🚀 Passo a Passo para Rodar Localmente

### 1. Criar o cluster kind (se ainda não existir)

```bash
kind create cluster --name desktop
```

### 2. Construir a imagem Docker da aplicação

```bash
cd kube-news
docker compose build
```

### 3. Carregar a imagem nos nodes do cluster

> ⚠️ Obrigatório em clusters kind — os nodes são containers isolados e não compartilham o daemon Docker do host.

```bash
kind load docker-image kube-news-kubenews:latest --name desktop
```

### 4. Aplicar o manifesto

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

### 5. Verificar os pods

```bash
kubectl get pods -n kubenews
```

Saída esperada (pode levar ~30s para ficarem `Running`):
```
NAME                        READY   STATUS    RESTARTS
kubenews-xxxxxxxxxx-xxxxx   1/1     Running   0
kubenews-xxxxxxxxxx-xxxxx   1/1     Running   0
postgre-0                   1/1     Running   0
```

### 6. Acessar a aplicação

```bash
kubectl port-forward svc/kubenews 8080:80 -n kubenews
```

Abra o navegador em: **http://localhost:8080**

---

## 🔍 Comandos Úteis

```bash
# Ver todos os recursos do namespace
kubectl get all -n kubenews

# Verificar logs da aplicação
kubectl logs -l app=kubenews -n kubenews --tail=50

# Verificar logs do banco
kubectl logs postgre-0 -n kubenews --tail=30

# Verificar uso de recursos
kubectl top pods -n kubenews

# Descrever um pod (útil para debugar)
kubectl describe pod <nome-do-pod> -n kubenews

# Testar endpoints de saúde (com port-forward ativo)
curl http://localhost:8080/health
curl http://localhost:8080/ready
curl http://localhost:8080/metrics

# Remover tudo do cluster
kubectl delete namespace kubenews

# Recarregar imagem após rebuild
docker compose build
kind load docker-image kube-news-kubenews:latest --name desktop
kubectl rollout restart deployment/kubenews -n kubenews
```

---

## ⚠️ Observações para Produção

Os ajustes desta documentação são voltados para **ambiente local de desenvolvimento/testes**. Para produção, considere:

| Item | Recomendação |
|---|---|
| Secrets | Usar solução externa (Vault, AWS Secrets Manager, Sealed Secrets) |
| Imagem | Publicar em registry privado e remover `imagePullPolicy: Never` |
| Replicas | Ajustar conforme carga real + HorizontalPodAutoscaler |
| LoadBalancer | Usar MetalLB, ingress controller (nginx/traefik) ou cloud provider |
| TLS | Configurar certificado via cert-manager + Ingress |
| Backup Postgres | Configurar CronJob de backup do PVC |

---

*Documentação gerada em 28/03/2026.*
