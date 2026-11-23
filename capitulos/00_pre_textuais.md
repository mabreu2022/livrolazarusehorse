# ELEMENTOS PRÉ-TEXTUAIS

\newpage

<!-- FOLHA DE ROSTO -->
<div style="text-align: center; margin-top: 100px;">

# DESENVOLVIMENTO DE APIS REST MODERNAS COM HORSE E LAZARUS

### Arquitetura Limpa, Firebird 5.0 e Deploy em Produção

<br><br>

## MAURÍCIO ABREU

<br><br><br><br>

**1ª Edição**  
**São Paulo — Brasil**  
**2026**

</div>

\newpage

<!-- FICHA CATALOGRÁFICA SUGERIDA -->
\vspace*{\fill}

<div style="border: 1px solid #1E293B; padding: 25px; margin: 20px 40px; font-size: 0.9em; line-height: 1.5; color: #1E293B; background-color: #FFFFFF;">

**Dados Internacionais de Catalogação na Publicação (CIP)**  
*(Câmara Brasileira do Livro, SP, Brasil)*

---

Abreu, Maurício.  
&nbsp;&nbsp;&nbsp;&nbsp;Desenvolvimento de APIs REST Modernas com Horse e Lazarus: Arquitetura Limpa, Firebird 5.0 e Deploy em Produção / Maurício Abreu. — 1. ed. — São Paulo : Edição do Autor, 2026.  
&nbsp;&nbsp;&nbsp;&nbsp;Formato: 16 cm × 23 cm (Padrão UICLAP).  
&nbsp;&nbsp;&nbsp;&nbsp;Bibliografia.  

&nbsp;&nbsp;&nbsp;&nbsp;ISBN: 978-65-00-00000-0  

&nbsp;&nbsp;&nbsp;&nbsp;1. Computação — Engenharia de Software. 2. Free Pascal Compiler (FPC). 3. Lazarus IDE. 4. Horse Web Framework. 5. Bancos de Dados Relacionais — Firebird 5.0. 6. Arquitetura de Software — Clean Architecture e SOLID. 7. Web Services RESTful — JSON. 8. Servidores HTTP e Deploy em Produção (Linux/Docker/Nginx). I. Título.

---

<div style="text-align: right; margin-top: 10px;">
**CDU 004.41:004.738.5**  
**CDD 005.133**  
</div>

</div>

\vspace*{\fill}

\newpage

<!-- DEDICATÓRIA -->
\vspace*{\fill}

<div style="text-align: right; margin-left: 35%; font-style: italic; color: #1E293B; line-height: 1.8;">

*Aos meus familiares, cujo apoio incondicional, amor e paciência transformaram longas noites de pesquisa e compilação em realidade.*

*A toda a vibrante comunidade mundial de Object Pascal, Free Pascal e Lazarus, que mantém viva, resiliente e moderna uma das mais brilhantes tecnologias de engenharia de software da história da computação.*

</div>

\vspace*{\fill}

\newpage

<!-- EPÍGRAFE -->
\vspace*{\fill}

<div style="text-align: right; margin-left: 30%; font-style: italic; color: #1E293B; line-height: 1.6;">

> "Simplicidade é pré-requisito para confiabilidade."  
> — **Edsger W. Dijkstra**

<br>

> "Programas devem ser escritos para que as pessoas os leiam, e apenas incidentalmente para que as máquinas os executem."  
> — **Harold Abelson & Gerald Jay Sussman**

</div>

\vspace*{\fill}

\newpage

<!-- PREFÁCIO -->
# PREFÁCIO

Durante mais de duas décadas, o ecossistema Object Pascal foi amplamente consagrado pelo desenvolvimento de aplicações desktop de altíssima performance, com interfaces ricas, conexão direta com bancos de dados relacionais e entregáveis consubstanciados em binários compilados nativamente, autossuficientes e velozes. Milhares de indústrias, instituições bancárias, hospitais e softwares de automação comercial foram — e continuam sendo — impulsionados pela solidez dessa tecnologia.

Contudo, a evolução arquitetural da computação corporativa impôs uma nova dinâmica. O advento das arquiteturas distribuídas, a consolidação dos microsserviços, a proliferação desenfreada de dispositivos móveis e a onipresença dos frontends baseados em Single Page Applications (SPAs) reposicionaram o centro gravitacional do desenvolvimento de software: as APIs RESTful tornaram-se a espinha dorsal de qualquer ecossistema tecnológico contemporâneo.

Diante desse cenário, instalou-se no mercado um mito equivocado: o de que o ecossistema Pascal pertenceria ao passado, relegado à manutenção de sistemas legados de desktop, enquanto as soluções backend modernas exigiriam obrigatoriamente ecossistemas baseados em interpretadores pesados, máquinas virtuais consumidoras de gigabytes de memória RAM ou runtimes com ciclos constantes de Garbage Collection que introduzem pausas imprevisíveis na latência das requisições.

Este livro nasce exatamente para quebrar essa falácia com rigor científico, profundidade de engenharia e métricas de produção.

A combinação entre o **Free Pascal Compiler (FPC)**, o ambiente integrado **Lazarus**, o framework web **Horse** e o motor de banco de dados relacional **Firebird 5.0** representa uma das pilhas tecnológicas mais eficientes, seguras, econômicas e velozes disponíveis na engenharia de software atual. Estamos tratando de binários executáveis puros (ELF no Linux e PE no Windows), que consomem poucos megabytes de memória RAM em repouso, iniciam em frações de milissegundo, atendem a dezenas de milhares de requisições por segundo com latência na casa dos microssegundos e operam com estabilidade inabalável em servidores virtuais de baixo custo.

No entanto, construir serviços de missão crítica com FPC e Lazarus exige muito mais do que simplesmente arrastar componentes para um DataModule. Exige domínio sobre programação multithread preemptiva, sincronização rigorosa de memória, arquitetura desacoplada via interfaces, pooling de conexões thread-safe e pipelines modernos de entrega contínua com Linux, Docker e Nginx.

Este livro foi concebido como um manual definitivo de engenharia aplicada. Aqui não há espaços para códigos pela metade, pseudo-exemplos "Hello World" descolados da realidade ou teorias sem aplicabilidade prática. Ao longo de 20 módulos densos e meticulosamente estruturados, o leitor construirá uma plataforma SaaS completa de Gestão de Ordens de Serviço e Faturamento Multi-Tenant, enfrentando todos os desafios que um arquiteto de software encontra no mundo real.

Seja você um desenvolvedor Pascal experiente que busca modernizar seu ferramental para a nuvem, ou um engenheiro de software oriundo de outras linguagens interessado em descobrir o poder da compilação nativa pura, esta obra oferece a trilha técnica definitiva para transformar seus conhecimentos em sistemas backend de alta performance.

Boa jornada de estudos e excelente compilação!

**Maurício Abreu**  
*Arquiteto de Software e Engenheiro de Sistemas*

\newpage

<!-- SOBRE O AUTOR -->
# SOBRE O AUTOR

**Maurício Abreu** é Engenheiro de Software Sênior, Arquiteto de Soluções Backend e especialista em desenvolvimento de alta performance no ecossistema Object Pascal (Delphi e Free Pascal / Lazarus), além de atuar no design de infraestruturas distribuídas, bancos de dados relacionais e ambientes conteinerizados.

Com sólida trajetória na indústria de software corporativo, é fundador e diretor de tecnologia na **Conect Solutions TI**, empresa dedicada à engenharia de software de missão crítica, consultoria arquitetural e modernização de ecossistemas empresariais para médias e grandes corporações.

Ao longo de sua carreira, liderou a concepção e implementação de soluções de alta concorrência nas áreas de automação comercial, emissão fiscal de documentos eletrônicos, integrações bancárias, plataformas de faturamento e arquiteturas multi-tenant, combinando a robustez dos binários compilados nativamente com as melhores práticas mundiais de Engenharia de Software, incluindo Clean Architecture, Domain-Driven Design (DDD) e pipelines automatizados de DevOps.

Além de sua atuação prática no mercado corporativo, Maurício dedica-se ativamente ao fomento da comunidade técnica de Free Pascal e Lazarus no Brasil e no exterior, produzindo conteúdo avançado, ministrando treinamentos e defendendo o uso racional, pragmático e performático do Object Pascal moderno em ambientes de nuvem e microsserviços.

\newpage

<!-- COMO USAR ESTE LIVRO -->
# COMO USAR ESTE LIVRO

Este livro foi concebido como uma obra técnica de referência e, simultaneamente, como um guia prático de engenharia editorial. Para extrair o máximo proveito da leitura e das implementações, recomendamos observar os seguintes aspectos estruturais e metodológicos.

## Organização da Obra em Cinco Blocos

A obra está estruturada em 20 módulos didáticos e progressivos, agrupados em cinco blocos conceituais:

1. **Bloco I — Fundamentos do Horse e Servidores Nativos em Lazarus (Módulos 01 a 04):** Apresenta a base conceitual do protocolo HTTP sob a ótica do compilador nativo, a arquitetura interna do Horse sobre o `fphttpserver`, a gestão de threads com `cthreads`, roteamento avançado, versionamento e semântica estrita de códigos HTTP com o padrão RFC 7807.
2. **Bloco II — Pipeline de Middlewares, Serialização JSON e Segurança (Módulos 05 a 08):** Desmistifica o padrão *Chain of Responsibility*, a criação de middlewares de auditoria, correlação e rate limiting, serialização de dados de alta performance com `fpjson` e `Jhonson`, tratamento global e seguro de exceções, culminando na implementação completa de autenticação stateless com tokens JWT e refresh tokens persistidos.
3. **Bloco III — Arquitetura Limpa e Persistência com Firebird 5.0 (Módulos 09 a 13):** Aplica os princípios de Clean Architecture, inversão de controle e contratos de interfaces no Lazarus. Explora o banco Firebird 5.0 com charset UTF8 e colunas IDENTITY, detalha a construção de um pool de conexões thread-safe à prova de vazamentos e implementa a camada de dados completa com transações controladas, paginação eficiente e filtros dinâmicos protegidos contra injeção SQL.
4. **Bloco IV — Recursos Avançados, Integrações e Qualidade (Módulos 14 a 17):** Aborda o streaming de arquivos binários com baixo consumo de memória, o consumo de APIs externas com `fphttpclient` e Webhooks seguros, a documentação viva da API com especificação OpenAPI 3.0 / Swagger UI embarcada e a automação de testes unitários e de integração com FPCUnit para esteiras de integração contínua (CI/CD).
5. **Bloco V — Compilação, Performance e Deploy em Produção (Módulos 18 a 20):** Detalha as diretivas de compilação avançadas do FPC para geração de binários minúsculos e ultrarrápidos, diagnóstico de vazamento de memória com `HeapTrc`, benchmarks sob estresse extremo, configuração de serviços nativos no Linux (`systemd`) e Windows Service, e a arquitetura completa de publicação em produção com Docker multi-stage, Nginx como proxy reverso e certificados SSL/TLS automáticos.

---

## Convenções Tipográficas e Caixas de Destaque

Para facilitar a leitura visual nas dimensões de 16 cm × 23 cm (padrão editorial UICLAP), foram adotadas convenções rígidas:

- **Código-Fonte em Object Pascal:** Todas as listagens de código foram formatadas respeitando o limite estrito de **72 caracteres por linha**, evitando quebras artificiais de linha na impressão.
- **Diretivas de Compilação:** Todos os exemplos em Object Pascal contêm explicitamente o cabeçalho `{$mode objfpc}{$H+}` ou `{$mode delphi}{$H+}` quando aplicável, assegurando total reprodutibilidade.
- **Caixas de Alerta Especializadas:** Ao longo dos módulos, você encontrará blocos estruturados que sinalizam orientações críticas:

> **Nota de Arquitetura:**  
> Destaca decisões estruturais de design, padrões de projeto aplicados, padrões de baixo acoplamento e separação de responsabilidades.

> **Atenção Thread-Safety:**  
> Sinaliza pontos críticos de concorrência entre threads, sincronização de memória, riscos de condições de corrida (*race conditions*) e bloqueios mútuos (*deadlocks*).

> **Boas Práticas FPC:**  
> Orientações específicas sobre o comportamento interno do Free Pascal Compiler, alocação e desalocação correta de memória, contagem de referências e diretivas de otimização.

---

## Projeto Prático Unificado: ConnectOSApi

Ao longo de toda a obra, não trabalharemos com fragmentos soltos ou exemplos artificiais de brinquedo. Desenvolveremos incrementalmente uma aplicação corporativa robusta: a **ConnectOSApi**, uma API RESTful de Gestão de Ordens de Serviço e Faturamento em arquitetura Multi-Tenant.

O código-fonte integral e organizado do projeto está hospedado no diretório `codigo_fonte/connect_os_api/`, estruturado nas seguintes camadas:

```
codigo_fonte/connect_os_api/
├── database/
│   └── schema_fb5.sql          # DDL completo Firebird 5.0
├── deploy/
│   ├── connect-os-api.service  # Unit de servico systemd
│   ├── docker-compose.yml      # Orquestracao API + Firebird 5.0
│   ├── Dockerfile              # Build multi-stage FPC Linux
│   └── nginx.conf              # Proxy reverso e balanceador
└── src/
    ├── ConnectOSApi.lpi        # Projeto Lazarus
    ├── ConnectOSApi.lpr        # Ponto de entrada do executavel
    ├── Controllers/            # Endpoints HTTP Horse
    ├── Core/                   # Pool de conexao, Middlewares, Utils
    ├── DTOs/                   # Data Transfer Objects
    ├── Interfaces/             # Contratos das camadas desacopladas
    ├── Models/                 # Entidades de dominio
    ├── Repositories/           # Acesso a dados Firebird 5.0
    └── Services/               # Regras de negocio e validacoes
```

\newpage

<!-- CONFIGURAÇÃO DO AMBIENTE DE LABORATÓRIO -->
# CONFIGURAÇÃO DO AMBIENTE DE LABORATÓRIO

Para reproduzir os exemplos, executar os testes e compilar o projeto prático deste livro, recomendamos a montagem de um ambiente de desenvolvimento padronizado. O ambiente pode ser configurado tanto em ambiente **Microsoft Windows 11** quanto em **Linux (Ubuntu 24.04 LTS)**. Em produção, focaremos na compilação nativa para Linux x86_64.

---

## 1. Requisitos Mínimos de Sistema

- **Processador:** Arquitetura x86_64 (Intel Core i3 / AMD Ryzen 3 ou superior).
- **Memória RAM:** Mínimo de 4 GB (Recomendado: 8 GB ou mais para execução conjunta de containers Docker e IDE).
- **Armazenamento:** 5 GB de espaço livre em disco SSD.
- **Sistemas Operacionais Homologados:**
  - Windows 10 / 11 (64-bit).
  - Linux Ubuntu 22.04 LTS ou 24.04 LTS (64-bit).

---

## 2. Configurando o Ambiente Windows 11

### Passo 2.1: Instalação do Lazarus e Free Pascal Compiler
1. Acesse o portal oficial do Lazarus ([https://www.lazarus-ide.org/](https://www.lazarus-ide.org/)) ou o repositório no SourceForge.
2. Baixe o instalador de 64 bits: `lazarus-3.4-fpc-3.2.2-win64.exe` (ou versão superior correspondente à versão estável).
3. Execute o instalador como Administrador. Recomendamos instalar no caminho padrão sem espaços acentuados, como `C:\lazarus`.
4. Certifique-se de que o diretório dos binários do FPC (`C:\lazarus\fpc\3.2.2\bin\x86_64-win64`) seja adicionado à variável de ambiente `PATH` do sistema.

### Passo 2.2: Instalação do Gerenciador de Pacotes Boss
O **Boss** é o gerenciador de dependências padrão do ecossistema Horse:
1. Acesse o repositório oficial do Boss no GitHub (`https://github.com/HashLoad/boss/releases`).
2. Baixe o executável `boss.exe` correspondente à versão estável para Windows.
3. Crie o diretório `C:\Tools\Boss\` e mova o executável para este local.
4. Adicione `C:\Tools\Boss\` ao `PATH` do Windows.
5. Abra o terminal (PowerShell ou Prompt de Comando) e digite:
```powershell
boss --version
```
A versão do Boss deverá ser exibida com sucesso.

### Passo 2.3: Instalação do Banco de Dados Firebird 5.0
1. Acesse a página de downloads do Firebird ([https://firebirdsql.org/en/firebird-5-0/](https://firebirdsql.org/en/firebird-5-0/)).
2. Baixe o instalador oficial de 64 bits: `Firebird-5.0.x-windows-x64.exe`.
3. Durante a instalação:
   - Selecione a opção **SuperServer** (recomendado para maior economia e concorrência).
   - Marque a instalação como Serviço do Windows com inicialização automática.
   - Marque a opção para copiar a biblioteca de cliente (`fbclient.dll`) para a pasta de sistema (`System32`) ou mantenha cópia na pasta do seu projeto.
   - Defina a senha do usuário `SYSDBA` (sugerimos a clássica `masterkey` para o ambiente local de testes).
4. Verifique se o serviço está ativo executando no PowerShell:
```powershell
Get-Service FirebirdServerDefaultInstance
```

---

## 3. Configurando o Ambiente Linux Ubuntu 24.04 LTS

Em ambientes de servidor e em nossa esteira de desenvolvimento profissional, o Linux é a plataforma de escolha.

### Passo 3.1: Instalação das Bibliotecas Básicas e Compilador FPC
Abra o terminal bash e execute os comandos de atualização e instalação:

```bash
# Atualizacao de repositorios locais
sudo apt update && sudo apt upgrade -y

# Dependencias essenciais de compilacao e desenvolvimento
sudo apt install -y build-essential git curl wget unzip psmisc

# Instalacao do Free Pascal Compiler e Lazarus
sudo apt install -y fpc fpc-source lazarus
```

Verifique as versões instaladas executando:
```bash
fpc -iV
lazbuild --version
```

### Passo 3.2: Instalando o Boss no Linux
Execute o script oficial de instalação automática via `curl`:

```bash
curl -sSfL \
  https://raw.githubusercontent.com/HashLoad/boss/master/get.sh | bash
```

Valide se o comando está disponível no terminal:
```bash
boss --version
```

### Passo 3.3: Instalação do Servidor Firebird 5.0 no Ubuntu
O Firebird 5.0 está disponível nos repositórios oficiais e pacotes oficiais:

```bash
# Instalacao do pacote Firebird 5.0 Server
sudo apt install -y firebird5.0-server firebird5.0-utils libfbclient2

# Verificacao do status do servico no systemd
sudo systemctl status firebird5.0
```
Durante a instalação, o assistente solicitará a criação da senha administrativa do `SYSDBA`. Anote essa senha para utilizar em nossos arquivos de configuração de ambiente.

---

## 4. Utilitários Complementares de Desenvolvimento e Diagnóstico

1. **Cliente Gráfico de Banco de Dados:**
   - **DBeaver Community** ([https://dbeaver.io/](https://dbeaver.io/)): Excelente suporte nativo ao Firebird com JDBC, suporte a visualização de DDL, planos de execução e edição de dados.
   - **FlameRobin** ([http://www.flamerobin.org/](http://www.flamerobin.org/)): Ferramenta leve, nativa e rápida específica para Firebird.
2. **Utilitários de Teste de APIs HTTP:**
   - **cURL:** Utilitário nativo de linha de comando para chamadas HTTP/REST.
   - **Postman** ou **Insomnia:** Clientes gráficos modernos para testes de requisições e automação de coleções.
   - **wrk** ou **k6:** Ferramentas para benchmarks e testes de estresse de alta concorrência.

Com o ambiente devidamente preparado e validado, você está pronto para ingressar no Módulo 01 e desvendar a anatomia profunda do Horse sobre o Free Pascal.
