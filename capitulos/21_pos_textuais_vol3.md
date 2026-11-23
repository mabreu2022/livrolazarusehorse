# Elementos Pós-Textuais — Volume 3

---

## Glossário Técnico Geral da Trilogia

**ACID:** Propriedades de Atomicidade, Consistência, Isolamento e Durabilidade.

**Circuit Breaker:** Padrão de resiliência que interrompe temporariamente 
chamadas a serviços externos falhos para evitar saturação de recursos locais.

**Cmem:** Unit do Free Pascal que redireciona alocações de memória para a 
`glibc` (malloc/free) para evitar contenção em servidores multi-threaded.

**Docker Multi-Stage:** Técnica de criação de imagens que utiliza um contêiner 
para compilação e descarta o compilador, mantendo apenas o binário final.

**Exponential Backoff:** Cálculo de tempo de espera progressivo ($2^t$) em 
tentativas de repetição de chamadas de rede.

**FPCUnit:** Framework de testes unitários xUnit nativo do Free Pascal.

**Graceful Shutdown:** Encerramento controlado interceptando `SIGTERM` sem 
derrubar requisições HTTP ativas.

**HeapTrc:** Unidade diagnóstica de heap (`-gh`) para detectar vazamentos 
de memória no FPC.

**LimitNOFILE:** Limite de descritores de arquivos no systemd para suportar 
milhares de conexões de sockets TCP simultâneas.

**OpenAPI 3.0:** Padrão internacional para especificação e documentação de 
APIs RESTful em formato JSON.

**Smartlinking:** Otimização do compilador FPC (`-XX`) que elimina rotinas 
e units não utilizadas no binário final.

**systemd:** Sistema de gerenciamento e supervisão de daemons no Linux.

---

## Referências Bibliográficas Consolidadas

1. **CANTÙ, Marco.** *Object Pascal Handbook*. Scotts Valley: Embarcadero, 2021.
2. **FIREBIRD PROJECT.** *Firebird 5.0 Reference Manual*. 2024.
3. **FREE PASCAL DEVELOPMENT TEAM.** *Free Pascal Compiler Guide*. 2023.
4. **GAMMA, Erich et al.** *Design Patterns*. Boston: Addison-Wesley, 1994.
5. **MARTIN, Robert C.** *Clean Architecture*. Boston: Prentice Hall, 2017.
6. **MESZAROS, Gerard.** *xUnit Test Patterns: Refactoring Test Code*. Boston: Addison-Wesley, 2007.
7. **NEWMAN, Sam.** *Building Microservices*. 2. ed. O'Reilly, 2021.
8. **NOTTINGHAM, Mark; WILDE, Erik.** *RFC 7807: Problem Details*. IETF, 2016.

---

## Colofão Editorial da Trilogia

```text
=====================================================================
            ESPECIFICACOES EDITORIAIS — VOLUME 3
=====================================================================
Titulo:      Desenvolvimento de APIs REST Modernas com Horse e Lazarus
Subtitulo:   Volume 3: Integrações, Qualidade de Software, DevOps 
             e Deploy em Produção
Autor:       Maurício Abreu
Editora:     Conect Solutions TI & Publicações Técnicas Independentes
Plataforma:  UICLAP — Impressão Sob Demanda (Print on Demand)

Formato:     16 cm x 23 cm (160 mm x 230 mm)
Papel Miolo: Offset Branco 75 g/m² ou Pólen Natural 80 g/m²
Capa:        Cartão 250 g/m² com Laminação Fosca (Soft-Touch)
Tipografia:  Família Inter / Merriweather / JetBrains Mono
Codigo:      Consolas / Liberation Mono (maximo 72 colunas)

Software:    Lazarus 3.x, FPC 3.2.2+, Docker Engine & Nginx
Local/Data:  São Paulo — Brasil, Novembro de 2026.
=====================================================================
```
