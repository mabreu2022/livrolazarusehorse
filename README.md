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
├── capitulos/            # 22 arquivos Markdown da obra completa (58.800+ palavras)
│   ├── 00_pre_textuais.md
│   ├── 01_anatomia_http_horse_fpc.md ... 20_nginx_proxy_reverso_ssl_docker.md
│   └── 21_pos_textuais.md
├── codigo_fonte/         # Projeto pratico ConnectOSApi completo
│   └── connect_os_api/
│       ├── boss.json     # Manifesto de dependencias do Boss
│       ├── database/     # DDL e seeds do Firebird 5.0
│       ├── deploy/       # Dockerfile multi-stage, docker-compose.yml e Nginx
│       ├── scripts/      # Scripts de build automatizado e testes k6
│       ├── src/          # Fontes Object Pascal (Clean Architecture)
│       │   ├── Controllers/
│       │   ├── Core/
│       │   ├── DTOs/
│       │   ├── Interfaces/
│       │   ├── Repositories/
│       │   └── Services/
│       └── tests/        # Suite de testes automatizados com FPCUnit
├── database/             # Script SQL DDL Firebird 5.0 multi-tenant (schema_fb5.sql)
├── output/               # PDF compilado pronto para impressao UICLAP (16x23 cm)
│   └── Livro_Horse_Lazarus_Mauricio_Abreu_16x23.pdf
└── scripts_build/        # Scripts Python de compilacao e auditoria editorial
    ├── check_formatting.py
    ├── compilar_livro.py
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

## 📄 Licença e Direitos Autorais

© 2026 Maurício Abreu. Todos os direitos reservados.  
O código-fonte deste projeto é disponibilizado sob a licença MIT para fins educacionais e de estudo.
