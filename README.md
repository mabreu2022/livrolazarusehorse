# Desenvolvimento de APIs REST Modernas com Horse e Lazarus
### Arquitetura Limpa, Firebird 5.0 e Deploy em Produção
**Autor:** Maurício Abreu  
**Padrão Editorial:** UICLAP 16 cm × 23 cm (160 mm × 230 mm)

---

## 📖 Sobre a Obra

Este repositório contém o código-fonte completo, scripts de banco de dados, infraestrutura de deploy e o manuscrito editorial do livro **"Desenvolvimento de APIs REST Modernas com Horse e Lazarus: Arquitetura Limpa, Firebird 5.0 e Deploy em Produção"**.

A obra é um guia prático e definitivo de engenharia de software para o ecossistema Object Pascal, abordando a construção de microsserviços e APIs corporativas de altíssima performance, escalabilidade e manutenibilidade.

---

## 🛠️ Stack Tecnológica

- **Linguagem & Compilador:** Object Pascal / Free Pascal Compiler (FPC 3.2.2+)
- **IDE:** Lazarus 3.x / 5.0
- **Framework Web:** [Horse Framework](https://github.com/HashLoad/horse) sobre `fphttpserver` (standalone)
- **Gerenciador de Pacotes:** [Boss CLI](https://github.com/HashLoad/boss)
- **Banco de Dados:** Firebird 5.0 (Charset UTF8, `IDENTITY`, `RETURNING`, MVCC)
- **Conectividade:** SQLdb (`TIBConnection`, `TSQLTransaction`) com Pool de Conexões Thread-Safe nativo
- **Documentação:** OpenAPI 3.0 / Swagger UI embarcado
- **Testes Automatizados:** FPCUnit (Modo console com relatórios JUnit XML)
- **Deploy & Produção:** Ubuntu 24.04 LTS, `systemd`, Nginx Reverse Proxy com SSL Let's Encrypt e Docker Multi-Stage

---

## 📂 Estrutura do Repositório

```text
├── capas/                # Templates HTML editáveis das capas dos 3 volumes
│   ├── capa_volume_1_aberta.html & capa_volume_1_frente.html
│   ├── capa_volume_2_aberta.html & capa_volume_2_frente.html
│   └── capa_volume_3_aberta.html & capa_volume_3_frente.html
├── capitulos/            # Manuscrito Markdown da obra completa (28 arquivos)
├── codigo_fonte/         # Projeto prático ConnectOSApi completo
│   └── connect_os_api/   # DTOs, Services, Controllers, Pool Thread-Safe, Docker
├── database/             # Script SQL DDL Firebird 5.0 multi-tenant (schema_fb5.sql)
├── output/               # PDFs do miolo prontos para impressão UICLAP (16x23 cm)
│   ├── Livro_Horse_Lazarus_Volume_1.pdf (111 págs)
│   ├── Livro_Horse_Lazarus_Volume_2.pdf (82 págs)
│   ├── Livro_Horse_Lazarus_Volume_3.pdf (66 págs)
│   ├── Livro_Horse_Lazarus_Volume_Unico.pdf (570 págs)
│   └── capas/            # Capas completas abertas (PDF + PNG 300 DPI) para UICLAP
│       ├── Capa_Completa_Volume_1_UICLAP.pdf & Capa_Aberta_Volume_1.png
│       ├── Capa_Completa_Volume_2_UICLAP.pdf & Capa_Aberta_Volume_2.png
│       └── Capa_Completa_Volume_3_UICLAP.pdf & Capa_Aberta_Volume_3.png
└── scripts_build/        # Scripts de automação editorial e compilação
    ├── check_formatting.py
    ├── compilar_livro.py
    ├── gerar_capas_uiclap.py
    └── estilo_uiclap_16x23.css
```

---

## 🚀 Como Executar o Projeto Prático (`ConnectOSApi`)

### 1. Pré-requisitos
- Free Pascal Compiler 3.2.2+ e Lazarus 3.0+
- Firebird Server 5.0 instalado e ativo na porta 3050
- Boss CLI instalado (`npm install -g @hashload/boss` ou binário oficial)

### 2. Configurando o Banco de Dados Firebird 5.0
Execute o script DDL no `isql` do Firebird:
```bash
isql -user SYSDBA -password masterkey
CREATE DATABASE 'localhost:/caminho/CONNECTOS.FDB' page_size 8192 default character set UTF8;
IN database/schema_fb5.sql;
EXIT;
```

### 3. Restaurando Dependências e Compilando
```bash
cd codigo_fonte/connect_os_api
boss install
fpc -B -Mobjfpc -Sh -O3 -XX -Xs -Fi./src -Fu./src/** src/ConnectOSApi.lpr -o./bin/connect_os_api
./bin/connect_os_api
```

### 4. Executando com Docker Compose (Stack Completa)
```bash
cd codigo_fonte/connect_os_api/deploy
docker compose up -d --build
```
Acesse a documentação Swagger interativa em: `http://localhost:9000/api/docs`

---

## 📑 Trilogia Editorial UICLAP (16 cm × 23 cm)

Para atender estritamente aos requisitos da plataforma de publicação **UICLAP** (limite máximo de 999 páginas por volume físico), a obra está disponível tanto na forma de **Trilogia em 3 Volumes Independentes** quanto em **Volume Único Consolidado**:

| Edição / Volume | Subtítulo e Escopo Temático | Módulos | Páginas | PDF Compilado |
| :--- | :--- | :---: | :---: | :--- |
| **Volume 1** | *Fundamentos do Horse, Roteamento, Middlewares e Segurança JWT* | 01 a 08 | 111 págs | `output/Livro_Horse_Lazarus_Volume_1.pdf` |
| **Volume 2** | *Arquitetura Limpa, Firebird 5.0 e Persistência de Dados* | 09 a 14 | 82 págs | `output/Livro_Horse_Lazarus_Volume_2.pdf` |
| **Volume 3** | *Integrações, Qualidade de Software, DevOps e Deploy em Produção* | 15 a 20 | 66 págs | `output/Livro_Horse_Lazarus_Volume_3.pdf` |
| **Volume Único** | *Edição Completa Consolidada (20 Módulos + Laboratórios)* | 01 a 20 | 570 págs | `output/Livro_Horse_Lazarus_Volume_Unico.pdf` |

### Como Compilar os Volumes

```bash
# 1. Auditoria de palavras e limite de 72 caracteres por linha de código
python scripts_build/check_formatting.py

# 2. Compilar os 3 Volumes da Trilogia UICLAP (padrão)
python scripts_build/compilar_livro.py

# 3. Compilar um volume específico
python scripts_build/compilar_livro.py --volume 1   # Volume 1
python scripts_build/compilar_livro.py --volume 2   # Volume 2
python scripts_build/compilar_livro.py --volume 3   # Volume 3
python scripts_build/compilar_livro.py --volume 0   # Volume Único Consolidado
```

Os arquivos PDFs finais gerados atendem integralmente à diagramação física (160 mm × 230 mm), tipografia light-mode para impressão offset/pólen e limites da UICLAP.

---

## 🎨 Capas Oficiais da Trilogia no Padrão UICLAP

As capas de cada volume foram projetadas respeitando estritamente o gabarito industrial da **UICLAP**:
- **Formato Fechado:** 16 cm × 23 cm (160 mm × 230 mm).
- **Sangria Industrial:** 5 mm em todas as quatro bordas externas (superior, inferior, esquerda e direita).
- **Altura Total com Sangria:** 240 mm (230 mm + 5 mm superior + 5 mm inferior).
- **Cálculo da Lombada (Spine):** Dimensionada precisamente para a quantidade exata de páginas de cada volume em papel Avena/Pólen 80g (~0.11 mm/folha + cola):
  - **Volume 1 (111 págs):** Lombada de **7.0 mm** | Largura Aberta Total: **337.0 mm × 240.0 mm**.
  - **Volume 2 (82 págs):** Lombada de **5.5 mm** | Largura Aberta Total: **335.5 mm × 240.0 mm**.
  - **Volume 3 (66 págs):** Lombada de **5.0 mm** | Largura Aberta Total: **335.0 mm × 240.0 mm**.

| Volume | Lombada | Dimensões Abertas | Arquivo PDF UICLAP | Capa Aberta (PNG 300 DPI) | Primeira Capa (PNG 300 DPI) |
| :--- | :---: | :---: | :--- | :--- | :--- |
| **Volume 1** | 7.0 mm | 337.0 × 240.0 mm | `output/capas/Capa_Completa_Volume_1_UICLAP.pdf` | `output/capas/Capa_Aberta_Volume_1.png` | `output/capas/Capa_Frente_Volume_1.png` |
| **Volume 2** | 5.5 mm | 335.5 × 240.0 mm | `output/capas/Capa_Completa_Volume_2_UICLAP.pdf` | `output/capas/Capa_Aberta_Volume_2.png` | `output/capas/Capa_Frente_Volume_2.png` |
| **Volume 3** | 5.0 mm | 335.0 × 240.0 mm | `output/capas/Capa_Completa_Volume_3_UICLAP.pdf` | `output/capas/Capa_Aberta_Volume_3.png` | `output/capas/Capa_Frente_Volume_3.png` |

### Como Gerar ou Atualizar as Capas
```bash
python scripts_build/gerar_capas_uiclap.py
```
O script compilará automaticamente os arquivos vetoriais em PDF e as imagens rasterizadas em 300 DPI na pasta `output/capas/`, além de salvar os templates HTML em `capas/`.

---

## 📄 Licença e Direitos Autorais

© 2026 Maurício Abreu. Todos os direitos reservados.  
O código-fonte deste projeto é disponibilizado sob a licença MIT para fins educacionais e de estudo.
