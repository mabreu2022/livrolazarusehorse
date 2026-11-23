# Elementos Pós-Textuais

---

## Glossário Técnico de Termos e Acrônimos

**ACID (Atomicidade, Consistência, Isolamento, Durabilidade):** Conjunto de 
propriedades fundamentais de transações em bancos de dados relacionais que 
garantem a integridade dos dados mesmo em caso de falhas, quedas de energia 
ou concorrência extrema.

**ANSI SQL (American National Standards Institute SQL):** Padrão normativo 
universal para a linguagem SQL. O Firebird 5.0 adota o padrão ANSI SQL:2008 
para cláusulas de paginação (`OFFSET ... FETCH NEXT ... ROWS ONLY`).

**Backoff Exponencial (Exponential Backoff):** Algoritmo de repetição em redes 
onde o tempo de espera entre tentativas sucessivas cresce exponencialmente 
($2^t$), evitando sobrecarga e tempestades de tráfego contra servidores 
receptores instáveis.

**Boss CLI:** Gerenciador de dependências e pacotes moderno para Delphi e 
Free Pascal, criado pela comunidade brasileira (Hashload), que automatiza a 
resolução de dependências e geração de caminhos via `boss.json` e `boss.lock`.

**Clean Architecture (Arquitetura Limpa):** Filosofia de design de software 
proposta por Robert C. Martin ("Uncle Bob") que organiza o sistema em camadas 
concêntricas (Entidades, Casos de Uso, Controladores e Detalhes de Infraestrutura), 
onde o sentido das dependências sempre aponta de fora para dentro.

**Correlation-ID:** Identificador único universal (UUID) gerado na borda da 
aplicação e propagado por todos os middlewares, logs e chamadas downstream, 
permitindo rastrear a jornada completa de uma requisição distribuída.

**Cthreads:** Unit de inicialização do Free Pascal no Linux e sistemas POSIX 
que registra a biblioteca `libpthread` no runtime do compilador. Obrigatória 
como primeiríssima unit de projetos multithread no Lazarus.

**DTO (Data Transfer Object):** Padrão de projeto que encapsula dados e os 
transporta entre camadas da aplicação ou entre cliente e servidor, sem 
comportamento de negócio complexo, otimizando a serialização JSON e a 
validação de entrada.

**FPC (Free Pascal Compiler):** Compilador profissional, nativo, de código 
aberto e multiplataforma para a linguagem Object Pascal, suportando dezenas de 
arquiteturas de processadores e sistemas operacionais.

**fphttpserver:** Módulo nativo da biblioteca `fcl-web` do Free Pascal que 
implementa um servidor HTTP multithread autônomo (*standalone*), servindo de 
motor de infraestrutura para o Horse no Lazarus.

**Garbage Collection (Firebird MVCC):** Processo interno do motor do Firebird 
encarregado de purgar versões antigas de registros (*back-versions*) que já 
não são mais visíveis por nenhuma transação ativa mais antiga (OAT).

**Graceful Shutdown:** Processo ordenado de encerramento de um serviço de 
rede, onde o servidor interrompe o recebimento de novas conexões, mas aguarda 
a finalização de transações e requisições em andamento antes de desligar.

**HeapTrc:** Unidade nativa de diagnóstico do Free Pascal (ativada com a 
flag `-gh`) que monitora todas as alocações e liberações de memória do heap, 
reportando blocos vazados ao término da execução com rastreamento de linhas.

**HMAC-SHA256 (Hash-based Message Authentication Code):** Algoritmo de 
autenticação criptográfica de mensagens que utiliza uma função hash em conjunto 
com uma chave secreta compartilhada, amplamente empregado na assinatura de 
Webhooks e tokens JWT.

**Horse:** Framework web minimalista, ultrarrápido e altamente extensível 
para Free Pascal e Delphi, inspirado no Express.js, operando sobre o padrão 
de pipeline de middlewares.

**Idempotência:** Propriedade de uma operação pela qual a aplicação do 
mesmo comando múltiplas vezes produz exatamente o mesmo resultado de estado 
que uma única execução, essencial para o processamento resiliente de Webhooks.

**JWT (JSON Web Token):** Padrão aberto da RFC 7519 que define uma forma 
compacta e autocontida para transmissão segura de informações entre partes 
como um objeto JSON assinado digitalmente.

**Lazarus IDE:** Ambiente de desenvolvimento integrado (IDE) rápido, expansível 
e multiplataforma para o compilador Free Pascal, modelado para alta 
produtividade.

**Least Privilege (Princípio do Menor Privilégio):** Prática de segurança da 
informação na qual uma entidade (usuário ou processo daemon) possui apenas os 
privilégios e permissões estritamente necessários para desempenhar sua função.

**MVCC (Multi-Version Concurrency Control):** Mecanismo de controle de 
concorrência no qual leituras nunca bloqueiam escritas e escritas nunca 
bloqueiam leituras, através da manutenção de múltiplas versões históricas 
de cada registro em disco.

**Nginx:** Servidor web reverso de alta performance, balanceador de carga 
e proxy HTTP/HTTPS conhecido pelo consumo diminuto de recursos e modelo de 
arquitetura orientada a eventos assíncronos.

**OAT (Oldest Active Transaction):** Identificador da transação ativa mais 
antiga no Firebird. Seu avanço determina a linha de corte para a coleta de 
lixo do banco de dados.

**OpenAPI 3.0:** Especificação padrão e agnóstica a linguagens para descrição 
e documentação formal de interfaces de programação de aplicações (APIs) RESTful.

**Path Traversal (ou Directory Traversal):** Vulnerabilidade de segurança em 
que um atacante manipula variáveis de arquivo com sequências como `../` para 
acessar ou sobrescrever diretórios confidenciais fora da pasta pretendida.

**Pool de Conexões:** Mecanismo de gerenciamento de recursos que mantém um 
conjunto pré-aquecido de conexões físicas com o banco de dados prontas para uso, 
eliminando o custo computacional de conectar e desconectar a cada requisição.

**RFC 7807 (Problem Details for HTTP APIs):** Padrão normativo do IETF que 
estabelece um formato JSON consistente para comunicação de erros em APIs HTTP, 
incluindo campos como `type`, `title`, `status`, `detail` e `instance`.

**Smartlinking:** Capacidade do compilador e linkeditor do FPC de descartar 
procedimentos, funções e seções de código que nunca são referenciadas na 
aplicação, reduzindo drasticamente o tamanho do arquivo executável final.

**systemd:** Sistema de inicialização e gerenciador de serviços padrão no 
ecossistema Linux moderno, responsável pela supervisão, reinicialização e 
gerenciamento de daemons de produção.

**Unit of Work:** Padrão de arquitetura de persistência que mantém uma lista 
de objetos de negócio afetados por uma transação e coordena a gravação e o 
comprometimento atômico das alterações no banco de dados.

---

## Referências Bibliográficas e Leituras Recomendadas

1. **ALBAHARI, Joseph; ALBAHARI, Ben.** *C# 10 in a Nutshell: The Definitive Reference*. Sebastopol: O'Reilly Media, 2022. (Referência em concorrência e padrões de threads).
2. **CANTÙ, Marco.** *Object Pascal Handbook: Complete Guide to the Language*. Scotts Valley: Embarcadero Technologies, 2021.
3. **FIELDING, Roy Thomas.** *Architectural Styles and the Design of Network-based Software Architectures*. Tese (Doutorado em Ciência da Computação) — University of California, Irvine, 2000. (Dissertação original que concebeu o estilo arquitetural REST).
4. **FIREBIRD PROJECT.** *Firebird 5.0 Reference Manual: Language and Architecture*. Firebird Project Documentation, 2024. Disponível em: <https://firebirdsql.org>.
5. **FREE PASCAL DEVELOPMENT TEAM.** *Free Pascal Compiler: Reference Guide and Language Reference (FPC 3.2.2)*. FPC Core Team, 2023. Disponível em: <https://freepascal.org>.
6. **GAMMA, Erich et al.** *Design Patterns: Elements of Reusable Object-Oriented Software*. Boston: Addison-Wesley, 1994. (Padrões Chain of Responsibility, Unit of Work e Factory).
7. **LAZARUS DEVELOPMENT TEAM.** *Lazarus IDE Documentation: Component and Run-Time Libraries*. Lazarus Foundation, 2024. Disponível em: <https://lazarus-ide.org>.
8. **MARTIN, Robert C.** *Clean Architecture: A Craftsman's Guide to Software Structure and Design*. Boston: Prentice Hall, 2017.
9. **NEWMAN, Sam.** *Building Microservices: Designing Fine-Grained Systems*. 2. ed. Sebastopol: O'Reilly Media, 2021.
10. **NOTTINGHAM, Mark; WILDE, Erik.** *RFC 7807: Problem Details for HTTP APIs*. Internet Engineering Task Force (IETF), 2016. Disponível em: <https://datatracker.ietf.org/doc/html/rfc7807>.
11. **RICHARDSON, Leonard; RUBY, Sam.** *RESTful Web Services*. Sebastopol: O'Reilly Media, 2007.

---

## Índice Remissivo

- **A**
  - ACID, 88, 122
  - Alocação de Memória, 18, 45, 178
  - Anexos e Arquivos, 142
  - Assinatura HMAC-SHA256, 85, 155
  - Autenticação JWT, 82
- **B**
  - Balanceamento de Carga, 202
  - Benchmarks (wrk / k6), 184
  - Boss CLI, 28
- **C**
  - Circuit Breaker, 158
  - Clean Architecture, 92
  - `cmem`, 181
  - Commit Retaining (Perigos de uso), 124
  - Concorrência e Threads, 16, 114
  - CORS, 72
  - `cthreads`, 17, 186
- **D**
  - Daemons, 190
  - DTOs (Data Transfer Objects), 65, 126
  - Deadlocks, 125, 134
  - Docker e Multi-stage Build, 205
- **E**
  - Encerramento Gracioso (Graceful Shutdown), 193
  - Exceções Customizadas, 76
- **F**
  - Firebird 5.0, 102, 112
  - `fphttpserver`, 15, 34
  - `fpjson` e JSON Parser, 62
- **G**
  - Garbage Collection no Firebird, 124
  - `GENERATED AS IDENTITY`, 104
- **H**
  - `HeapTrc` (Diagnóstico de Vazamentos), 32, 172, 183
  - Horse Framework, 14, 38
  - HTTP Status Codes, 52
- **I**
  - Idempotência em Webhooks, 156
  - Interfaces (`IInterface`), 94
- **L**
  - Lazarus IDE, 26
  - Limite de Descritores (`LimitNOFILE`), 192
- **M**
  - Middlewares (Pipeline e Next), 48
  - Mocks e Test Doubles, 168
  - Multi-tenancy, 106, 128
- **N**
  - Nginx, 200
- **O**
  - OAT (Oldest Active Transaction), 124
  - `OFFSET ... FETCH NEXT`, 136
  - OpenAPI 3.0 e Swagger, 160
  - Otimizações do FPC (`-O3`), 179
- **P**
  - Paginação, 135
  - Path Traversal (Prevenção), 145
  - Pool de Conexões Thread-Safe, 112
  - Problem Details (RFC 7807), 56
- **R**
  - Rate Limiting, 50
  - Refresh Tokens, 86
  - Repositórios e Serviços, 96
- **S**
  - Smartlinking (`-XX`), 180
  - SQL Injection (Prevenção e Whitelist), 138
  - Streaming com `TFileStream`, 144
  - `systemd`, 191
- **T**
  - `TCriticalSection`, 116
  - Testes Unitários e FPCUnit, 166
  - Transações Atômicas, 123
- **U**
  - Unit of Work, 125
  - UPX (Compressão de Binário), 182
  - UTF-8 Collation, 105
- **W**
  - Webhooks, 154
  - Windows Service, 196

---

## Colofão Editorial

```text
=====================================================================
                    ESPECIFICACOES EDITORIAIS DA OBRA
=====================================================================
Titulo:      Desenvolvimento de APIs REST Modernas com Horse e Lazarus
Subtitulo:   Arquitetura Limpa, Firebird 5.0 e Deploy em Produção
Autor:       Maurício Abreu
Editora:     Conect Solutions TI & Publicações Técnicas Independentes
Plataforma:  UICLAP — Impressão Sob Demanda (Print on Demand)

Formato:     16 cm x 23 cm (160 mm x 230 mm)
Papel Miolo: Offset Branco 75 g/m² ou Pólen Natural 80 g/m²
Capa:        Cartão 250 g/m² com Laminação Fosca (Soft-Touch)
Tipografia:  Família Inter / Segoe UI (Corpo: 10 pt / Entrelinha: 1.5)
Codigo:      Consolas / Liberation Mono (8.5 pt, max 72 colunas)

Software:    Lazarus 3.x / 5.0 & Free Pascal Compiler 3.2.2+
Banco:       Firebird RDBMS 5.0.1
Pipeline:    Python Markdown-to-PDF / Headless Chromium Engine
Local/Data:  São Paulo — Brasil, Novembro de 2026.
=====================================================================
```
