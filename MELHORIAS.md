# 📋 Melhorias Implantadas — Kube-News

Documento com todas as melhorias aplicadas na sessão de revisão e hardening do ambiente local Docker.

---

## 1. Dockerfile (`src/Dockerfile`)

### Antes
```dockerfile
FROM node:21.6.0-alpine3.18
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 8080
CMD ["node", "server.js"]
```

### Depois
```dockerfile
FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY . .

EXPOSE 8080

USER node

CMD ["node", "server.js"]
```

### Mudanças e Motivações

| # | Mudança | Motivação |
|---|---|---|
| 1 | `node:21.6.0-alpine3.18` → `node:20-alpine` | Node 21 não é LTS. Node 20 tem suporte de longo prazo (LTS), mais estável e com patches de segurança garantidos |
| 2 | `npm install` → `npm ci --omit=dev` | `npm ci` garante instalação reprodutível baseada no `package-lock.json`. `--omit=dev` exclui dependências de desenvolvimento, reduzindo o tamanho da imagem |
| 3 | Adicionado `USER node` | A aplicação deixa de rodar como root dentro do container, reduzindo a superfície de ataque em caso de exploração |

---

## 2. Docker Compose (`compose.yaml`)

### Antes
```yaml
services:
  postgre:
    image: postgres:13.13
    ports:
     - 5432:5432
    environment:
      POSTGRES_PASSWORD: pg1234
      POSTGRES_USER: kubenews
      POSTGRES_DB: kubenews
  kubenews:
    image: fabricioveronez/kube-news:v1
    depends_on:
      - postgre
    build:
      context: ./src
      dockerfile: ./Dockerfile
    ports:
      - 8080:8080
    environment:
      DB_DATABASE: kubenews
      DB_USERNAME: kubenews
      DB_PASSWORD: pg1234
      DB_HOST: postgre

networks:
  kubenews_net:
    driver: bridge
```

### Depois
```yaml
services:
  postgre:
    image: postgres:13.13
    environment:
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_USER: ${DB_USERNAME}
      POSTGRES_DB: ${DB_DATABASE}
    networks:
      - kubenews_net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USERNAME} -d ${DB_DATABASE}"]
      interval: 10s
      timeout: 5s
      retries: 5

  kubenews:
    build:
      context: ./src
      dockerfile: ./Dockerfile
    depends_on:
      postgre:
        condition: service_healthy
    ports:
      - 8080:8080
    environment:
      DB_DATABASE: ${DB_DATABASE}
      DB_USERNAME: ${DB_USERNAME}
      DB_PASSWORD: ${DB_PASSWORD}
      DB_HOST: postgre
    networks:
      - kubenews_net

networks:
  kubenews_net:
    driver: bridge
```

### Mudanças e Motivações

| # | Mudança | Motivação |
|---|---|---|
| 1 | Removida exposição da porta `5432` do Postgres ao host | O banco de dados não precisa ser acessível fora da rede Docker. Expor a porta ao host (`0.0.0.0:5432`) representa risco de acesso não autorizado |
| 2 | Serviços adicionados à rede `kubenews_net` | A rede estava declarada mas nenhum serviço a utilizava (bug). Agora app e banco comunicam pela rede isolada |
| 3 | Adicionado `healthcheck` no Postgres | Garante que o container do banco só seja considerado saudável quando estiver de fato aceitando conexões |
| 4 | `depends_on` com `condition: service_healthy` | O app só sobe após o Postgres estar pronto, evitando crashes por tentativa de conexão prematura |
| 5 | Credenciais movidas para variáveis de ambiente (`${VAR}`) | Senhas não ficam mais expostas em texto puro no `compose.yaml`, referenciando o arquivo `.env` |
| 6 | Removida `image: fabricioveronez/kube-news:v1` do serviço `kubenews` | Redundante junto com `build`. Para uso local, apenas o `build` é necessário |

---

## 3. Novos Arquivos Criados

### `.env`
Arquivo com as variáveis de ambiente para o Docker Compose. Mantém credenciais fora do código-fonte.

```env
DB_DATABASE=kubenews
DB_USERNAME=kubenews
DB_PASSWORD=pg1234
```

> ⚠️ **Importante:** Este arquivo **não deve ser commitado** no Git. Adicione ao `.gitignore`.

### `src/.dockerignore`
Evita que arquivos desnecessários (ou sensíveis) sejam copiados para dentro da imagem Docker.

```
node_modules
npm-debug.log
.env
```

| Entrada | Motivação |
|---|---|
| `node_modules` | Dependências locais não devem entrar na imagem; são instaladas via `npm ci` |
| `npm-debug.log` | Arquivo de log de erros do npm, irrelevante na imagem |
| `.env` | Impede que variáveis sensíveis sejam copiadas para dentro da imagem |

---

## 4. Verificação de Saúde (Health Check)

Após todas as correções, a aplicação foi validada com os seguintes resultados:

| Verificação | Resultado |
|---|---|
| `GET /health` | ✅ `{"state":"up","machine":"..."}` |
| `GET /ready` | ✅ `Ok` |
| `GET /metrics` | ✅ Prometheus respondendo |
| Container `kubenews` | ✅ Up, CPU: ~0.5%, Memória: ~26 MB |
| Container `postgre` | ✅ Up **(healthy)**, CPU: ~0%, Memória: ~33 MB |
| Porta 5432 exposta ao host | ✅ Corrigido — apenas interna |

---

## 5. Riscos Residuais (Não Corrigidos Nesta Sessão)

Os itens abaixo foram identificados mas estão fora do escopo do ambiente local de desenvolvimento:

| Risco | Detalhe | Recomendação |
|---|---|---|
| Endpoints sem autenticação | `/unhealth`, `/unreadyfor/:seconds` e `/metrics` são públicos | Proteger com middleware de autenticação em produção |
| Sem rate limiting | API sem limite de requisições | Adicionar middleware como `express-rate-limit` |
| Sem HTTPS | Tráfego em texto puro | Usar TLS/proxy reverso (nginx, Traefik) em produção |
| Sem persistência no Postgres | Dados perdidos ao recriar o container | Adicionar `volumes` no compose para produção |

---

*Documentação gerada em 28/03/2026.*
