# Kubernetes — Expondo Aplicações com NodePort

## O que é NodePort?

O **NodePort** é um tipo de `Service` no Kubernetes que expõe uma aplicação externamente, abrindo uma porta diretamente em **todos os nós do cluster**. Assim, qualquer pessoa com acesso ao IP do nó pode acessar a aplicação sem precisar de `port-forward`.

```
Usuário → IP do Nó : NodePort → Service → Pod
```

---

## Faixa de portas

O Kubernetes reserva o intervalo **30000–32767** para NodePort. Você pode definir manualmente ou deixar o Kubernetes escolher automaticamente dentro dessa faixa.

---

## Criando um Service do tipo NodePort

### Exemplo de manifesto YAML

```yaml
apiVersion: v1
kind: Service
metadata:
  name: minha-app
  namespace: default
spec:
  type: NodePort
  selector:
    app: minha-app        # deve coincidir com o label do Deployment
  ports:
    - protocol: TCP
      port: 80            # porta interna do Service (dentro do cluster)
      targetPort: 8080    # porta que a aplicação escuta no container
      nodePort: 30080     # porta exposta no nó (opcional — se omitido, será sorteada)
```

### Aplicar o manifesto

```bash
kubectl apply -f service.yaml
```

---

## Descobrindo o IP do nó

```bash
kubectl get nodes -o wide
```

Saída esperada:

```
NAME       STATUS   ROLES    AGE   VERSION   INTERNAL-IP     EXTERNAL-IP
node-01    Ready    <none>   5d    v1.29.0   192.168.1.100   <none>
```

Use o valor da coluna **INTERNAL-IP** (ou **EXTERNAL-IP** se disponível).

---

## Acessando a aplicação

Com o IP do nó e a nodePort definida, acesse pelo navegador ou curl:

```bash
# Exemplo com curl
curl http://192.168.1.100:30080

# Ou no navegador
http://192.168.1.100:30080
```

---

## Verificando o Service criado

```bash
# Listar services
kubectl get svc

# Detalhes do service
kubectl describe svc minha-app
```

Saída esperada do `get svc`:

```
NAME         TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
minha-app    NodePort   10.96.45.123   <none>        80:30080/TCP   2m
```

O formato `80:30080/TCP` significa:
- `80` → porta interna do cluster
- `30080` → porta exposta no nó

---

## Exemplo completo (Deployment + Service)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minha-app
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: minha-app
  template:
    metadata:
      labels:
        app: minha-app
    spec:
      containers:
        - name: minha-app
          image: nginx:latest
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: minha-app
  namespace: default
spec:
  type: NodePort
  selector:
    app: minha-app
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
      nodePort: 30080
```

Aplicar tudo de uma vez:

```bash
kubectl apply -f deployment.yaml
```

---

## Comparativo: port-forward vs NodePort

| Característica        | port-forward             | NodePort                      |
|-----------------------|--------------------------|-------------------------------|
| Uso recomendado       | Desenvolvimento/debug    | Testes e ambientes locais     |
| Trava o terminal?     | Sim (a menos que use `&`)| Não                           |
| Acesso externo        | Apenas local             | Qualquer host com acesso ao nó|
| Configuração          | Nenhuma                  | Manifesto YAML do Service     |
| Porta exposta         | Escolhida pelo usuário   | Faixa 30000–32767             |

---

## Dicas

- Em clusters **locais (Minikube)**, obtenha a URL diretamente:
  ```bash
  minikube service minha-app --url
  ```
- Em clusters **Kind**, o NodePort pode exigir mapeamento extra no `kind-config.yaml`.
- Para **produção**, prefira **Ingress + LoadBalancer** ao invés de NodePort.
