# Elementos Pré-Textuais — Volume 1

<div class="folha-rosto">
  <h1 style="border:none; text-align:center; font-size: 22pt; margin-top: 40pt;">
    Desenvolvimento de APIs REST Modernas com Horse e Lazarus
  </h1>
  <h2 style="border:none; text-align:center; font-size: 14pt; color: #475569; font-weight: 500;">
    Volume 1: Fundamentos do Horse, Roteamento, Middlewares e Segurança JWT
  </h2>
  <div style="text-align:center; margin-top: 60pt; font-size: 13pt; font-weight: 600;">
    Maurício Abreu
  </div>
  <div style="text-align:center; margin-top: 100pt; font-size: 10pt; color: #64748B;">
    Conect Solutions TI & Publicações Técnicas<br>
    São Paulo — Brasil<br>
    2026
  </div>
</div>

<div class="newpage"></div>

## Ficha Catalográfica

```text
---------------------------------------------------------------------
Dados Internacionais de Catalogação na Publicação (CIP)
Bibliotecária Responsável: Registro Editorial Padrão
---------------------------------------------------------------------

A162d   Abreu, Maurício.
        Desenvolvimento de APIs REST Modernas com Horse e Lazarus: 
        Arquitetura Limpa, Firebird 5.0 e Deploy em Produção — 
        Volume 1: Fundamentos do Horse, Roteamento, Middlewares 
        e Segurança JWT / Maurício Abreu. – São Paulo: Edição do 
        Autor / Conect Solutions TI, 2026.
        Formato: 16 x 23 cm.

        ISBN 978-65-00-00000-0 (Volume 1 - Impresso)
        ISBN 978-65-00-00000-0 (Série Completa)

        1. Free Pascal. 2. Lazarus IDE. 3. Horse Framework. 
        4. APIs RESTful. 5. Middlewares HTTP. 6. JSON Web Tokens.
        I. Título. II. Série: Trilogia APIs REST com Lazarus.

                                                    CDD 005.133
                                                    CDU 004.43
---------------------------------------------------------------------
```

<div class="newpage"></div>

## Dedicatória

> *Aos desenvolvedores da comunidade Object Pascal e Free Pascal em todo o* 
> *mundo, que provam diariamente que elegância sintática, performance bruta* 
> *nativa e disciplina arquitetural constroem softwares eternos.*

<div class="newpage"></div>

## Prefácio do Volume 1

Bem-vindo ao primeiro volume da trilogia definitiva sobre o desenvolvimento 
de APIs REST corporativas com Free Pascal e Lazarus.

Por décadas, a comunidade Delphi e Pascal construiu a espinha dorsal dos 
sistemas de gestão empresarial (ERPs) na América Latina e no mundo. No 
entanto, com a revolução da computação em nuvem, microsserviços e frontends 
baseados em SPA (Single Page Applications) e dispositivos móveis, muitos 
acreditaram que o ecossistema Pascal estaria restrito a aplicações desktop 
legadas.

Este primeiro volume desconstrói categoricamente esse mito. Apresentamos o 
**Horse Framework**, uma solução minimalista, de altíssima vazão e inspirada 
nas melhores práticas da web moderna, rodando sobre o servidor nativo 
`fphttpserver` do Free Pascal Compiler (FPC).

Neste Volume 1, você aprenderá desde a anatomia de baixo nível do ciclo de 
vida HTTP e gerenciamento de threads (`cthreads`) até a construção de uma 
esteira completa de middlewares profissionais (Logging, Correlation-ID, 
Rate Limiting, CORS) e a implementação de uma camada de autenticação stateless 
robusta com JSON Web Tokens (JWT) e Refresh Tokens.

Boa leitura e excelente codificação!

**Maurício Abreu**  
*Novembro de 2026*

<div class="newpage"></div>

## Sumário do Volume 1

- **Bloco I: Fundamentos do Horse e Servidores Nativos em Lazarus**
  - Módulo 01: Anatomia de um Servidor HTTP no Free Pascal e Lazarus
  - Módulo 02: Setup do Lazarus, Gerenciador Boss e Primeiro Servidor
  - Módulo 03: Roteamento Avançado, Verbos HTTP e Captura de Parâmetros
  - Módulo 04: Dominando Requisições, Respostas e Status HTTP com RFC 7807
- **Bloco II: Pipeline de Middlewares, Serialização JSON e Segurança**
  - Módulo 05: Pipeline de Middlewares e Encadeamento com Next
  - Módulo 06: Serialização JSON de Alta Performance com fpjson e Jhonson
  - Módulo 07: Configuração Segura de CORS e Tratamento Global de Exceções
  - Módulo 08: Autenticação Segura com JWT, Claims e Refresh Tokens
- **Elementos Pós-Textuais**
  - Glossário Técnico do Volume 1
  - Referências Bibliográficas
  - Colofão Editorial

---
