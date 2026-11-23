# Elementos Pós-Textuais — Volume 2

---

## Glossário Técnico do Volume 2

**Clean Architecture:** Organização de software em camadas concêntricas 
onde a regra de negócio independe do banco de dados e do framework web.

**Commit Puro vs CommitRetaining:** Diferença fundamental no Firebird entre 
encerrar a transação liberando recursos ou mantê-la aberta travando a OAT.

**Connection Pool:** Estrutura thread-safe que mantém conexões físicas 
abertas e prontas para uso por múltiplas threads simultâneas.

**Identity Columns:** Recurso nativo do Firebird 5.0 para geração automática 
de chaves primárias sem necessidade de triggers manuais.

**MVCC:** Controle de concorrência multiversão onde leituras nunca travam 
escritas no Firebird.

**OAT (Oldest Active Transaction):** Marcador da transação ativa mais 
antiga que define o limite da coleta de lixo.

**Path Traversal:** Ataque em que manipuladores de arquivos tentam escapar 
do diretório permitido utilizando `../`.

**Streaming com TFileStream:** Envio fracionado de arquivos do disco para 
o socket TCP sem alocação integral em memória RAM.

**Unit of Work:** Padrão que agrupa operações de múltiplos repositórios 
sob uma única transação atômica.

---

## Referências Bibliográficas — Volume 2

1. **FIREBIRD PROJECT.** *Firebird 5.0 Reference Manual: Architecture & SQL*. Firebird Foundation, 2024. Disponível em: <https://firebirdsql.org>.
2. **FOWLER, Martin.** *Patterns of Enterprise Application Architecture*. Boston: Addison-Wesley, 2002.
3. **MARTIN, Robert C.** *Clean Architecture: A Craftsman's Guide to Software Structure and Design*. Boston: Prentice Hall, 2017.
4. **NEWMAN, Sam.** *Building Microservices*. 2. ed. Sebastopol: O'Reilly Media, 2021.

---

## Colofão Editorial — Volume 2

```text
=====================================================================
            ESPECIFICACOES EDITORIAIS — VOLUME 2
=====================================================================
Titulo:      Desenvolvimento de APIs REST Modernas com Horse e Lazarus
Subtitulo:   Volume 2: Arquitetura Limpa, Firebird 5.0 e Persistência 
             de Dados
Autor:       Maurício Abreu
Editora:     Conect Solutions TI & Publicações Técnicas Independentes
Plataforma:  UICLAP — Impressão Sob Demanda (Print on Demand)

Formato:     16 cm x 23 cm (160 mm x 230 mm)
Papel Miolo: Offset Branco 75 g/m² ou Pólen Natural 80 g/m²
Capa:        Cartão 250 g/m² com Laminação Fosca (Soft-Touch)
Tipografia:  Família Inter / Merriweather / JetBrains Mono
Codigo:      Consolas / Liberation Mono (maximo 72 colunas)

Software:    Lazarus 3.x, FPC 3.2.2+ & Firebird RDBMS 5.0
Local/Data:  São Paulo — Brasil, Novembro de 2026.
=====================================================================
```
