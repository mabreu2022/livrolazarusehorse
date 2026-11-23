# Módulo 20: Nginx Proxy Reverso, SSL Gratuito, Multi-Stage Docker e Deploy

Chegamos ao ápice da nossa jornada de engenharia de software: a publicação 
da nossa API REST em um ambiente de produção de classe empresarial. Embora 
o Horse rodando sobre o `fphttpserver` do Free Pascal ofereça uma vazão 
bruta extraordinária, expor o servidor Pascal diretamente à internet 
pública na porta 80 ou 443 contraria as melhores práticas de segurança e 
arquitetura de redes.

A arquitetura de referência recomendada para microsserviços modernos 
posiciona o **Nginx** como Proxy Reverso na borda (*edge*), encarregado de:
- Efetuar a terminação criptográfica SSL/TLS com certificados gratuitos 
  e renovação automática via **Let's Encrypt / Certbot**.
- Distribuir a carga (*Load Balancing*) entre múltiplos processos Horse.
- Mitigar ataques de negação de serviço (DDoS) e absorver requisições malformadas.
- Injetar cabeçalhos de segurança corporativos (HSTS, CSP, X-Frame-Options).

Neste módulo, projetaremos a infraestrutura completa de deploy, incluindo 
configurações avançadas do Nginx, containerização multi-stage com **Docker** 
(gerando imagens ultracompactas inferiores a 80 MB) e orquestração de toda a 
pilha (API Lazarus + **Firebird 5.0** + Nginx) com **Docker Compose**.

---

## 1. Objetivos de Aprendizagem do Módulo

Ao concluir este módulo, o leitor estará plenamente capacitado a:
1. Projetar e configurar o **Nginx** como Proxy Reverso de alta performance 
   para a API Horse.
2. Implementar terminação SSL/TLS com certificados A+ emitidos pelo Let's 
   Encrypt através do utilitário Certbot com renovação automática.
3. Configurar balanceamento de carga (*Load Balancing*) com algoritmos 
   `round-robin` e `least_conn` entre múltiplas instâncias da API.
4. Construir um `Dockerfile` multi-stage otimizado para Free Pascal, gerando 
   uma imagem final de produção minimalista e hipersegura.
5. Orquestrar a pilha completa de produção (Nginx + API + Firebird 5.0) 
   utilizando `docker-compose.yml` com redes virtuais isoladas.
6. Garantir a preservação do endereço IP original do cliente utilizando os 
   cabeçalhos `X-Forwarded-For` e `X-Real-IP`.

---

## 2. Fundamentação Conceitual e Arquitetural

### 2.1 A Topologia de Produção: Edge Nginx + Upstream Cluster

Na topologia de produção recomendada, o tráfego externo proveniente da 
internet é recebido pelo Nginx nas portas padrão 80 (HTTP) e 443 (HTTPS). O 
Nginx decodifica a criptografia TLS e repassa o tráfego HTTP puro para um 
cluster de nós da API Horse escutando em portas locais (ex: 9000 e 9001):

```
+--------------------------------------------------------------------+
|                  TOPOLOGIA DE PRODUCAO CONNECTOS                   |
|                                                                    |
|  [Internet / Clientes HTTP / Mobile / SPAs]                        |
|         |                                                          |
|         | Porta 443 (HTTPS com Certbot / Let's Encrypt)            |
|         v                                                          |
|  +---------------------------------------------------------------+ |
|  | Nginx Proxy Reverso & Load Balancer                           | |
|  | - Forca HTTPS (redirect 80 -> 443)                            | |
|  | - Termina criptografia TLS (economiza CPU da API)             | |
|  | - Aplica buffer de requisicao e rate limit na borda           | |
|  +---------------------------------------------------------------+ |
|         |                                                          |
|         +---> Repassa via Upstream Cluster (HTTP Local)            |
|         |                                                          |
|         +-----------------------+-----------------------+          |
|         |                                               |          |
|         v                                               v          |
|  +----------------------------+   +----------------------------+   |
|  | Instancia Horse 1 (:9000)  |   | Instancia Horse 2 (:9001)  |   |
|  | (PID 1042 - cgroup)        |   | (PID 1043 - cgroup)        |   |
|  +----------------------------+   +----------------------------+   |
|         |                                               |          |
|         +-----------------------+-----------------------+          |
|                                 |                                  |
|                                 v                                  |
|                  +----------------------------+                    |
|                  | Firebird 5.0 Database      |                    |
|                  | (Porta 3050 - Pool Seguro) |                    |
|                  +----------------------------+                    |
+--------------------------------------------------------------------+
```

### 2.2 Vantagens da Terminação SSL no Nginx

Descarregar a responsabilidade criptográfica TLS para o Nginx traz 
vantagens decisivas:
- **Economia de CPU na Aplicação:** O Nginx possui rotinas em C altamente 
  otimizadas com aceleração por hardware (instruções AES-NI da CPU) para 
  handshake TLS.
- **Renovação Transparente:** O Certbot renova os certificados a cada 60 
  dias recarregando apenas a configuração do Nginx (`nginx -s reload`), 
  sem necessidade de reiniciar o binário da API Lazarus.
- **Protocolos Modernos:** Habilita facilmente HTTP/2 e HTTP/3 (QUIC) na 
  borda sem exigir alterações no runtime do FPC.

### 2.3 Multi-Stage Docker Build para Free Pascal

Um erro comum ao containerizar aplicações compiladas é utilizar uma única 
imagem base com o compilador completo instalado. Uma imagem Ubuntu com FPC, 
Lazarus e ferramentas de build facilmente ultrapassa 1.5 GB.

Com o recurso de **Multi-Stage Build**, dividimos o processo em dois estágios:
1. **Stage 1 (Builder):** Imagem com FPC 3.2.2 e código-fonte. O compilador 
   gera o executável nativo otimizado (`connect_os_api`).
2. **Stage 2 (Runner):** Imagem base mínima (`debian:bookworm-slim` ou 
   `ubuntu:24.04`), contendo apenas as bibliotecas dinâmicas essenciais 
   (`libfbclient2`, `libssl3`, `ca-certificates`). O binário compilado no 
   Stage 1 é copiado para cá e o compilador inteiro é descartado.

O resultado é uma imagem final de produção com **menos de 80 MB**, 
composta exclusivamente pelo binário estático e bibliotecas mínimas.

### 2.4 Otimização de Buffers e Conexões no Nginx

Para suportar dezenas de milhares de requisições simultâneas sem engasgos, 
o arquivo principal do Nginx (`/etc/nginx/nginx.conf`) deve ser ajustado 
para aproveitar o hardware moderno:
- `worker_processes auto;`: Spawna um processo de trabalho por núcleo de CPU.
- `worker_connections 4096;`: Permite até 4.096 conexões ativas por worker.
- `proxy_buffering on;`: Permite que o Nginx receba e armazene a resposta 
  rápida da API Horse em memória, liberando a thread do Free Pascal de 
  imediato enquanto o cliente lento baixa os dados pela internet móvel.
- `proxy_buffers 8 32k;`: Aloca buffers generosos em RAM antes de usar disco.

### 2.5 Estratégia de Deploy Sem Queda (*Zero-Downtime Deployment*)

Com a infraestrutura orquestrada em nós duplos (`api_node_1` e `api_node_2`), 
podemos aplicar atualizações de código sem interromper o atendimento aos 
usuários através de uma estratégia *Rolling Update*:
1. O Nginx direciona o tráfego exclusivamente para `api_node_1`.
2. O contêiner `api_node_2` é recriado e atualizado com a nova versão compilada.
3. O healthcheck confirma que `api_node_2` está saudável (`200 OK` no `/ping`).
4. O Nginx passa a encaminhar tráfego para `api_node_2`.
5. O contêiner `api_node_1` é atualizado seguindo o mesmo procedimento.

Nenhum usuário percebe lentidão ou recebe erro de conexão durante a migração.

---

## 3. Implementação Passo a Passo

### 3.1 Configuração Completa do Nginx (`connectos.conf`)

Criamos o arquivo de configuração do Nginx em 
`/etc/nginx/sites-available/connectos.conf`:

```nginx
# Cluster de balanceamento de carga da API Horse
upstream connectos_backend {
    least_conn; # Encaminha requisicoes para a instancia com menos carga
    server 127.0.0.1:9000 max_fails=3 fail_timeout=10s;
    server 127.0.0.1:9001 max_fails=3 fail_timeout=10s;
    keepalive 32;
}

# Redirecionamento obrigatorio de HTTP para HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name api.connectos.com.br;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

# Servidor seguro HTTPS com terminacao SSL
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name api.connectos.com.br;

    # Certificados gerenciados pelo Certbot / Let's Encrypt
    ssl_certificate 
        /etc/letsencrypt/live/api.connectos.com.br/fullchain.pem;
    ssl_certificate_key 
        /etc/letsencrypt/live/api.connectos.com.br/privkey.pem;

    # Criptografia SSL/TLS moderna (Classificacao SSL Labs A+)
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5:!3DES;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;

    # Cabecalhos de Seguranca Estritos
    add_header Strict-Transport-Security 
        "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Limite maximo de upload (compativel com o Modulo 14)
    client_max_body_size 50M;

    location / {
        proxy_pass http://connectos_backend;
        proxy_http_version 1.1;

        # Repasse de cabecalhos de conexao e keepalive
        proxy_set_header Connection "";
        proxy_set_header Host $host;

        # Preservacao do IP Real do Cliente
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Timeouts de comunicacao com o backend Horse
        proxy_connect_timeout 5s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }
}
```

### 3.2 Emissão Automática de Certificado SSL com Certbot

No servidor Ubuntu, emitimos o certificado com um único comando:

```bash
# 1. Instala o Certbot com plugin Nginx
sudo apt-get update && \
    sudo apt-get install -y certbot python3-certbot-nginx

# 2. Emite o certificado e configura caminhos SSL no Nginx
sudo certbot --nginx -d api.connectos.com.br --non-interactive \
    --agree-tos -m admin@connectos.com.br

# 3. Testa a renovacao automatica periodica
sudo certbot renew --dry-run
```

O Certbot adiciona um timer no `systemd` (`certbot.timer`) que verifica a 
validade dos certificados duas vezes ao dia e os renova automaticamente 
30 dias antes da expiração.

### 3.3 O `Dockerfile` Multi-Stage de Produção

Criamos o arquivo `Dockerfile` na raiz do projeto:

```dockerfile
# ===================================================================
# STAGE 1: Compilador e Construtor (Builder)
# ===================================================================
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# Instala compilador FPC e dependencias essenciais de build
RUN apt-get update && apt-get install -y \
    fpc \
    fpc-source \
    build-essential \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copia codigo-fonte do projeto
COPY . .

# Compila o binario final nativo com otimizacao -O3
RUN mkdir -p /app/bin && \
    fpc -B \
        -Mobjfpc \
        -Sh \
        -O3 \
        -XX \
        -Xs \
        -CX \
        -Fi/app/src \
        -Fu/app/src/** \
        -FE/app/bin \
        -o/app/bin/connect_os_api \
        /app/src/ConnectOSApi.lpr

# ===================================================================
# STAGE 2: Imagem de Producao Minimalista (Runner)
# ===================================================================
FROM ubuntu:24.04 AS runner

ENV DEBIAN_FRONTEND=noninteractive

# Bibliotecas dinamicas essenciais de tempo de execucao (sem FPC)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libssl3 \
    libfbclient2 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Cria usuario de sistema sem privilegios
RUN useradd -r -s /usr/sbin/nologin -d /app connectos

WORKDIR /app

# Cria diretorios de armazenamento e logs
RUN mkdir -p /app/storage /app/logs && \
    chown -R connectos:connectos /app

# Copia EXCLUSIVAMENTE o binario gerado no Stage 1
COPY --from=builder /app/bin/connect_os_api /app/connect_os_api
RUN chmod +x /app/connect_os_api && \
    chown connectos:connectos /app/connect_os_api

# Alterna para o usuario seguro
USER connectos

# Porta interna exposta
EXPOSE 9000

# Healthcheck interno do container
HEALTHCHECK --interval=15s --timeout=3s --retries=3 \
    CMD curl -f http://localhost:9000/ping || exit 1

ENTRYPOINT ["/app/connect_os_api"]
```

### 3.4 Orquestração Completa com `docker-compose.yml`

Criamos o arquivo `docker-compose.yml` integrando o banco Firebird 5.0, 
duas instâncias da API Horse e o Nginx:

```yaml
version: '3.8'

services:
  # -----------------------------------------------------------------
  # Banco de Dados Firebird 5.0
  # -----------------------------------------------------------------
  firebird:
    image: firebirdsql/firebird:5.0
    container_name: connectos_firebird
    restart: always
    environment:
      - ISC_PASSWORD=MasterKeyProducao2026!
      - FIREBIRD_DATABASE=CONNECTOS.FDB
    volumes:
      - firebird_data:/firebird/data
      - ./database/schema_fb5.sql:/docker-entrypoint-initdb.d/init.sql
    networks:
      - backend_net

  # -----------------------------------------------------------------
  # Instancia 1 da API Horse
  # -----------------------------------------------------------------
  api_node_1:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: connectos_api_1
    restart: always
    environment:
      - PORT=9000
      - FB_HOST=firebird
      - FB_DATABASE=/firebird/data/CONNECTOS.FDB
      - FB_USER=SYSDBA
      - FB_PASS=MasterKeyProducao2026!
    volumes:
      - storage_data:/app/storage
    depends_on:
      - firebird
    networks:
      - backend_net

  # -----------------------------------------------------------------
  # Instancia 2 da API Horse (Balanceamento de Carga)
  # -----------------------------------------------------------------
  api_node_2:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: connectos_api_2
    restart: always
    environment:
      - PORT=9000
      - FB_HOST=firebird
      - FB_DATABASE=/firebird/data/CONNECTOS.FDB
      - FB_USER=SYSDBA
      - FB_PASS=MasterKeyProducao2026!
    volumes:
      - storage_data:/app/storage
    depends_on:
      - firebird
    networks:
      - backend_net

  # -----------------------------------------------------------------
  # Proxy Reverso Nginx Borda
  # -----------------------------------------------------------------
  nginx:
    image: nginx:alpine
    container_name: connectos_nginx
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./deploy/nginx/connectos.conf:/etc/nginx/conf.d/default.conf:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
    depends_on:
      - api_node_1
      - api_node_2
    networks:
      - backend_net

networks:
  backend_net:
    driver: bridge

volumes:
  firebird_data:
  storage_data:
```

### 3.5 Script de Atualização Sem Queda (`deploy_update.sh`)

Para realizar a atualização contínua da aplicação em produção sem desconectar 
clientes ativos, criamos o script `deploy_update.sh`:

```bash
#!/usr/bin/env bash
# ===================================================================
# Script de Rolling Update com Zero Downtime — ConnectOS API
# ===================================================================

set -e

echo "==> Reconstruindo imagem Docker com a nova versao compilada..."
docker compose build api_node_1 api_node_2

echo "==> Atualizando no 1 (api_node_1)..."
docker compose up -d --no-deps api_node_1

echo "==> Aguardando no 1 responder ao healthcheck..."
docker compose exec api_node_1 curl -s -f http://localhost:9000/ping

echo "==> Atualizando no 2 (api_node_2)..."
docker compose up -d --no-deps api_node_2

echo "==> Aguardando no 2 responder ao healthcheck..."
docker compose exec api_node_2 curl -s -f http://localhost:9000/ping

echo "==> Recarregando configuracao do Nginx..."
docker compose exec nginx nginx -s reload

echo "==> Deploy concluido com sucesso sem nenhuma perda de conexao!"
```

---

## 4. Testando o Endpoint e Operações em Produção

### 4.1 Subindo a Infraestrutura com Docker Compose

```bash
# Constrói as imagens e inicia os containers em background
docker compose up -d --build

# Inspeciona o estado dos containers
docker compose ps
```

**Saída esperada:**
```text
NAME                 COMMAND                  SERVICE      STATUS
connectos_firebird   "/docker-entrypoint.…"   firebird     Up (healthy)
connectos_api_1      "/app/connect_os_api"    api_node_1   Up (healthy)
connectos_api_2      "/app/connect_os_api"    api_node_2   Up (healthy)
connectos_nginx      "/docker-entrypoint.…"   nginx        Up
```

### 4.2 Testando a Chamada Segura com Nginx e SSL

```bash
curl -i -X GET https://api.connectos.com.br/ping
```

**Resposta esperada com cabeçalhos de segurança:**
```http
HTTP/2 200 
server: nginx
date: Mon, 23 Nov 2026 10:30:00 GMT
content-type: application/json; charset=utf-8
strict-transport-security: max-age=31536000; includeSubDomains
x-content-type-options: nosniff
x-frame-options: DENY

{
  "status": "UP",
  "memory_heap_kb": 1280
}
```

### 4.3 Telemetria dos Contêineres com `docker stats`

Para auditar o impacto do balanceamento de carga e o isolamento de recursos 
em tempo real sob estresse, o comando nativo `docker stats` exibe as métricas 
vivas de cada componente:

```bash
docker stats \
  connectos_nginx connectos_api_1 connectos_api_2 connectos_firebird
```

**Métricas Típicas em Produção:**
- `connectos_api_1`: CPU flutuando entre 5% e 15%, Memória estável em 18 MB.
- `connectos_api_2`: Carga dividida identicamente pelo algoritmo `least_conn`.
- `connectos_firebird`: Cache de páginas aquecido, IO de disco otimizado.
- `connectos_nginx`: Consumo inferior a 12 MB de RAM, transmitindo centenas 
  de megabytes sem saturação.

Esse painel comprova a extrema eficiência e a leveza do ecossistema Free 
Pascal, entregando performance comparável a Go ou Rust com uma fração do 
consumo de hardware das stacks tradicionais.

---

## 5. Armadilhas Comuns e Troubleshooting no FPC/Lazarus

### 5.1 Perda do IP Real do Cliente no Horse
Ao colocar a API atrás do Nginx, `Req.RawWebRequest.RemoteAddr` passa a 
conter sempre `127.0.0.1` (o IP do próprio proxy). 
**Solução:** Sempre extraia o IP real inspecionando o cabeçalho 
`Req.Headers['X-Real-IP']` ou `Req.Headers['X-Forwarded-For']` injetado pelo 
Nginx no middleware de Rate Limiting ou Log de Auditoria.

### 5.2 Erro de Conexão com Firebird: "Connection Refused" no Docker
No `docker-compose.yml`, o parâmetro de host do banco não pode ser 
`localhost` ou `127.0.0.1`. Dentro da rede interna do Docker, cada container 
possui seu próprio endereço IP virtual. Utilize o nome do serviço 
definido no compose (`FB_HOST=firebird`), que o DNS interno do Docker 
resolverá automaticamente.

### 5.3 Erro "502 Bad Gateway" no Nginx
Se o Nginx retornar o status HTTP `502 Bad Gateway`, a causa é a incapacidade 
do proxy de estabelecer comunicação com o backend Horse:
1. Inspecione os logs do Nginx: `docker compose logs nginx | tail -n 20`.
2. Verifique se o container da API caiu por exceção não tratada: 
   `docker compose ps` (observe se o status está `Exit 1` ou `CrashLoop`).
3. Confirme se as portas internas coincidem (`PORT=9000` na API e `9000` 
   no bloco `upstream` do Nginx).

### 5.4 Permissões de Volume de Storage no Host Linux
Ao montar pastas locais do host no container (`/app/storage`), se o usuário 
do container (`connectos` com UID 1000) não tiver permissão de escrita no 
diretório físico do host, uploads dispararão `EStreamError: Access Denied`. 
No host, execute `sudo chown -R 1000:1000 ./storage` para garantir a posse.

---

## 6. Resumo Executivo e Checklist de Revisão

Concluímos com êxito a arquitetura completa de publicação corporativa da 
nossa API em Free Pascal e Lazarus, dotando o ecossistema de alta 
disponibilidade, segurança de ponta a ponta e containerização moderna.

### Checklist de Revisão
- [ ] O Nginx está configurado como proxy reverso com balanceamento de carga?
- [ ] O certificado SSL Let's Encrypt está ativo com renovação automática?
- [ ] Cabeçalhos de segurança HSTS e prevenção de clickjacking estão ativados?
- [ ] O `Dockerfile` multi-stage descarta o compilador, gerando imagem < 80 MB?
- [ ] A API roda sob usuário não-privilegiado (`USER connectos`) no container?
- [ ] O `docker-compose.yml` orquestra Firebird 5.0, API e Nginx com volumes persistentes?
