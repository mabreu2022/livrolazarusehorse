# Elementos Pré-Textuais — Volume 3

<div class="folha-rosto">
  <h1 style="border:none; text-align:center; font-size: 22pt; margin-top: 40pt;">
    Desenvolvimento de APIs REST Modernas com Horse e Lazarus
  </h1>
  <h2 style="border:none; text-align:center; font-size: 14pt; color: #475569; font-weight: 500;">
    Volume 3: Integrações, Qualidade de Software, DevOps e Deploy em Produção
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
        Volume 3: Integrações, Qualidade de Software, DevOps e 
        Deploy em Produção / Maurício Abreu. – São Paulo: Edição 
        do Autor / Conect Solutions TI, 2026.
        Formato: 16 x 23 cm.

        ISBN 978-65-00-00000-0 (Volume 3 - Impresso)
        ISBN 978-65-00-00000-0 (Série Completa)

        1. Free Pascal. 2. Lazarus IDE. 3. OpenAPI 3.0 / Swagger. 
        4. FPCUnit. 5. Docker Multi-Stage. 6. Nginx & SSL.
        I. Título. II. Série: Trilogia APIs REST com Lazarus.

                                                    CDD 005.133
                                                    CDU 004.43
---------------------------------------------------------------------
```

<div class="newpage"></div>

## Dedicatória

> *Aos profissionais de DevOps, SysAdmins e Engenheiros de Confiabilidade* 
> *(SRE) que mantêm os sistemas do mundo operando 24 horas por dia, 7 dias* 
> *por semana, com resiliência inabalável e código de alto nível.*

<div class="newpage"></div>

## Prefácio do Volume 3

Você alcançou o volume de coroação da nossa trilogia.

Nos Volumes 1 e 2, construímos a base da aplicação: o motor web Horse, os 
middlewares de proteção, a segurança JWT, os padrões de Arquitetura Limpa e a 
persistência atômica no banco de dados Firebird 5.0. No entanto, um software 
só gera valor real quando ultrapassa as fronteiras do ambiente local de 
desenvolvimento e opera de forma estável, segura e monitorada em produção.

O **Volume 3** é dedicado à integração corporativa, garantia de qualidade e 
engenharia de operações (DevOps). Você aprenderá a consumir APIs externas e 
reagir a Webhooks assíncronos com assinatura HMAC e idempotência; 
implementará documentação viva com o padrão **OpenAPI 3.0** e Swagger UI 
embarcado; construirá uma suíte de **testes automatizados com FPCUnit** 
e Mocks para integração em pipelines CI/CD; e dominará a otimização de 
compilação (`-O3`, `-Xs`, `-XX`, `cmem`), testes de carga com `wrk` e `k6`, 
configuração de daemons com `systemd` e Windows Services, e a implantação 
completa em nuvem com **Nginx**, **SSL Let's Encrypt** e **Docker Multi-Stage**.

Esteja pronto para levar suas habilidades em Object Pascal ao mais alto 
patamar do mercado mundial.

**Maurício Abreu**  
*Novembro de 2026*

<div class="newpage"></div>

## Sumário do Volume 3

- **Bloco IV: Recursos Avançados e Qualidade (Parte 2)**
  - Módulo 15: Consumo de APIs Externas, Webhooks e Resiliência HTTP
  - Módulo 16: Documentação Viva com OpenAPI 3.0 e Swagger UI Embarcado
  - Módulo 17: Testes Automatizados com FPCUnit, Mocks e CI/CD
- **Bloco V: Compilação, Performance e Deploy em Produção**
  - Módulo 18: Otimização do Compilador FPC, HeapTrc e Benchmarks de Carga
  - Módulo 19: Daemons de Produção com systemd e Windows Services
  - Módulo 20: Nginx Proxy Reverso, SSL Gratuito, Multi-Stage Docker e Deploy
- **Elementos Pós-Textuais da Trilogia**
  - Glossário Técnico Geral
  - Referências Bibliográficas Consolidadas
  - Índice Remissivo da Obra Completa
  - Colofão Editorial da Trilogia

---
