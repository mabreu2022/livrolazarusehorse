# MÓDULO 02: SETUP PROFISSIONAL NO LAZARUS COM BOSS E O PRIMEIRO SERVIDOR ESTRUTURADO

---

## 1. OBJETIVOS DE APRENDIZAGEM DO MÓDULO

Ao final deste módulo, você será capaz de:

1. Dominar o ecossistema de gerenciamento de dependências com o **Boss CLI**, compreendendo a função do manifesto `boss.json` e do arquivo de bloqueio de versões `boss.lock`.
2. Configurar o projeto do **Lazarus (`.lpi` e `.lpr`)** de forma independente de plataforma, garantindo caminhos de busca (`-Fu`, `-Fi`) portáveis entre Windows e Linux sem dependência da interface gráfica da IDE.
3. Estruturar a árvore de diretórios de uma API corporativa em camadas limpas, eliminando arquivos temporários e binários do controle de versão (`.gitignore`).
4. Implementar uma arquitetura de inicialização desacoplada, separando os pontos de entrada do servidor, a configuração de middlewares e a injeção dos controladores de rotas.
5. Construir o endpoint de monitoramento `/ping` fornecendo métricas de telemetria do Free Pascal (tempo de atividade, versão do runtime e estado do heap de memória) em formato JSON.

---

## 2. FUNDAMENTAÇÃO CONCEITUAL E ARQUITETURAL

No desenvolvimento corporativo contemporâneo, a reprodutibilidade de compilação é um requisito inegociável de engenharia. Um dos maiores entraves históricos do ecossistema Pascal residiu no gerenciamento manual de dependências: programadores costumavam baixar arquivos `.zip` de bibliotecas de terceiros, descompactá-los em diretórios arbitrários de seus computadores locais e adicionar manualmente caminhos absolutos nas opções de projeto da IDE.

Esse método artesanal introduz fragilidades graves:
- **Quebra em Pipelines de Integração Contínua (CI/CD):** Servidores de automação (como GitHub Actions, GitLab CI ou Jenkins) operam em contêineres sem interface visual e exigem que todas as dependências sejam restauradas de forma autônoma via linha de comando.
- **Incompatibilidade de Caminhos Absolutos:** Um caminho como `C:\Componentes\Horse\src` definido no Windows inviabiliza imediatamente a compilação do mesmo projeto em um servidor Linux ou na máquina de outro engenheiro de equipe.
- **Divergência Silenciosa de Versões (*Dependency Drift*):** Sem um arquivo de bloqueio estrito (*lockfile*), diferentes membros do time podem compilar o mesmo código-fonte utilizando versões ligeiramente distintas de uma mesma biblioteca, introduzindo bugs imprevisíveis e difíceis de rastrear em produção.

Para sanar essas deficiências de forma definitiva, adotamos o **Boss**, o gerenciador de dependências oficial do ecossistema Horse.

```
+-------------------------------------------------------------------+
|                        FLUXO DE DEPENDÊNCIAS                      |
+-------------------------------------------------------------------+
                                  |
                                  v
+-----------------------+                 +-------------------------+
|      boss.json        |                 |        boss.lock        |
| Declaração de pacotes |                 | Hash SHA e commit exato |
|   e versões alvo      |                 |   de cada dependência   |
+-----------------------+                 +-------------------------+
            |                                          |
            +--------------------+---------------------+
                                 |
                                 v
              [ Execução de: boss install ]
                                 |
                                 v
+-------------------------------------------------------------------+
|                       PASTA modules/                              |
|           Código-fonte de todas as dependências baixadas          |
+-------------------------------------------------------------------+
                                 |
                                 v
+-------------------------------------------------------------------+
|                   COMPILADOR FREE PASCAL (FPC)                    |
|       Lê os caminhos relativos: -Fumodules/**/src                 |
|       Compila binário nativo estático e autocontido               |
+-------------------------------------------------------------------+
```

### O Papel do boss.json e do boss.lock

O Boss funciona de maneira análoga aos gerenciadores consagrados da indústria, como o Cargo (Rust), Go Modules (Go) e npm (Node.js):

- **`boss.json`:** É o manifesto do projeto. Especifica o nome do pacote, a versão semântica da aplicação, a licença e a lista de dependências diretas exigidas pelo projeto.
- **`boss.lock`:** É o registro imutável do estado das dependências. Ele congela a URL exata do repositório Git, o commit de hash SHA e a tag de release utilizada na última restauração com sucesso. Esse arquivo **deve** ser comitado no repositório Git para garantir que qualquer máquina compile exatamente os mesmos bytes de código-fonte.
- **Diretório `modules/`:** É a pasta local onde o Boss clona o código das bibliotecas. Esse diretório **nunca** deve ser versionado no Git; ele deve figurar explicitamente no arquivo `.gitignore`.

### Pacotes do Lazarus (.lpk) vs. Boss CLI em Servidores de Produção

No desenvolvimento de aplicações desktop com o Lazarus, o mecanismo padrão de integração de componentes é o **Lazarus Package Manager**, corporificado em arquivos de pacote `.lpk`. Embora os pacotes `.lpk` sejam ideais para instalar componentes na paleta visual da IDE, eles introduzem atritos indesejáveis em projetos backend:
1. Muitas vezes exigem a recompilação da própria IDE Lazarus para registrar componentes visuais.
2. Demandam a execução da ferramenta `lazbuild` com arquivos de configuração de ambiente complexos dentro de servidores Linux headless.

Ao utilizar o Boss em conjunto com o FPC, nós tratamos o framework Horse e seus middlewares como **código-fonte puro** (*source-level dependencies*). O Free Pascal Compiler simplesmente compila os arquivos `.pas` das dependências diretamente para código-objeto (`.o` e `.ppu`) e realiza a vinculação estática (*static linking*) no binário final.

Essa abordagem confere vantagens decisivas:
- Compilação direta via linha de comando invocando diretamente o binário `fpc`, sem necessidade de instalar a interface gráfica do Lazarus em servidores de produção.
- Total isolamento de dependências por projeto: atualizar o Horse em um projeto não interfere em nenhum outro projeto existente no mesmo computador.

> **Nota de Arquitetura:**  
> A estrutura de compilação orientada a fontes locais via Boss permite gerar binários totalmente autocontidos no Linux. O binário final não depende de arquivos `.so` externos para a lógica da aplicação web, resultando em contêineres Docker incrivelmente enxutos (com menos de 25 MB) e deploys atômicos por simples cópia de arquivo.

---

## 3. IMPLEMENTAÇÃO PASSO A PASSO

A partir deste momento, abandonaremos os arquivos isolados e construiremos incrementalmente a espinha dorsal corporativa do nosso projeto prático: a **ConnectOSApi**.

### Passo 1: Inicializando o Manifesto de Dependências com o Boss

No diretório raiz do projeto prático (`codigo_fonte/connect_os_api/`), inicializaremos o projeto através do terminal executando o comando `boss init`:

```bash
cd codigo_fonte/connect_os_api
boss init
```

O utilitário fará perguntas interativas sobre o projeto. Responda conforme o padrão corporativo:
- **Package name:** `connect_os_api`
- **Description:** `API RESTful Corporativa com Horse e Firebird 5.0`
- **Version:** `1.0.0`
- **Main file:** `src/ConnectOSApi.lpr`
- **Author:** `Maurício Abreu`

Em seguida, instalaremos a versão mais recente e estável do Horse:

```bash
boss install github.com/HashLoad/horse
```

O Boss clonará o Horse para `modules/horse` e gerará automaticamente o arquivo `boss.json` e o `boss.lock`. O manifesto `boss.json` resultante terá a seguinte estrutura:

```json
{
  "name": "connect_os_api",
  "description": "API RESTful Corporativa com Horse e Firebird 5.0",
  "version": "1.0.0",
  "homepage": "",
  "main": "src/ConnectOSApi.lpr",
  "author": "Maurício Abreu",
  "license": "MIT",
  "dependencies": {
    "github.com/HashLoad/horse": "^3.1.8"
  }
}
```

---

### Passo 2: Configurando o Arquivo de Ignorados do Git (.gitignore)

Crie imediatamente o arquivo `.gitignore` na raiz de `codigo_fonte/connect_os_api/` para evitar que lixo de compilação e dependências pesadas poluam o repositório:

```gitignore
# Diretorio de dependencias do Boss
modules/

# Arquivos de saida de compilacao do Free Pascal
*.o
*.ppu
*.a
*.s
*.rst
*.compiled

# Binarios e executaveis gerados
bin/
lib/
*.exe
*.dll
*.so
*.dylib
ConnectOSApi

# Arquivos temporarios e de backup da IDE Lazarus
*.bak
*.lps
backup/
*~
```

---

### Passo 3: Criando a Unit de Controlador de Telemetria: Controllers.Ping.pas

Seguindo as regras de baixo acoplamento da Arquitetura Limpa, a lógica de atendimento dos endpoints nunca deve ser despejada dentro do arquivo `.lpr` principal. Criaremos a unit dedicada `src/Controllers/Controllers.Ping.pas`.

Esta unit demonstra como ler métricas internas do Free Pascal e formatar uma resposta de telemetria completa em conformidade com o limite de 72 caracteres por linha.

```pascal
{======================================================================}
{ Projeto: ConnectOSApi - API de Gestao e Faturamento Multi-Tenant     }
{ Unit   : Controllers.Ping                                            }
{ Papel  : Endpoints de telemetria, saude e métricas de memoria FPC    }
{======================================================================}
unit Controllers.Ping;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  Horse;

type
  { Classe estatica de registro de rotas do controlador }
  TControllersPing = class
  private
    class procedure DoGetPing(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
    class procedure DoGetMetrics(Req: THorseRequest; 
      Res: THorseResponse; Next: TNextProc);
  public
    class procedure Registry;
  end;

implementation

{ TControllersPing }

class procedure TControllersPing.DoGetPing(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vPayload: string;
begin
  vPayload := '{"status":"pong",' +
              '"servico":"ConnectOSApi",' +
              '"timestamp":"' + 
              FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', Now) + 
              '"}';

  Res.Send(vPayload)
     .Status(THTTPStatus.OK);
end;

class procedure TControllersPing.DoGetMetrics(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vHeapStatus: TFPCHeapStatus;
  vPayload: string;
begin
  { Leitura do estado do gerenciador de memoria do Free Pascal }
  vHeapStatus := GetFPCHeapStatus;

  vPayload := '{"servico":"ConnectOSApi",' +
              '"fpc_version":"' + {$I %FPCVERSION%} + '",' +
              '"target_cpu":"' + {$I %FPCTARGETCPU%} + '",' +
              '"target_os":"' + {$I %FPCTARGETOS%} + '",' +
              '"heap_usado_bytes":' + 
              IntToStr(vHeapStatus.CurrHeapUsed) + ',' +
              '"heap_alocado_bytes":' + 
              IntToStr(vHeapStatus.CurrHeapSize) + ',' +
              '"heap_maximo_bytes":' + 
              IntToStr(vHeapStatus.MaxHeapUsed) + '}';

  Res.Send(vPayload)
     .Status(THTTPStatus.OK);
end;

class procedure TControllersPing.Registry;
begin
  THorse.Get('/ping', @DoGetPing);
  THorse.Get('/api/v1/metrics', @DoGetMetrics);
end;

end.
```

> **Boas Práticas FPC:**  
> A função nativa `GetFPCHeapStatus` da biblioteca do Free Pascal retorna o registro `TFPCHeapStatus`. Com ele, podemos monitorar em tempo de execução exatamente quantos bytes de memória física o heap do FPC está retendo (`CurrHeapSize`) e quantos bytes estão efetivamente em uso pela aplicação (`CurrHeapUsed`). Essa métrica é crucial para identificar vazamentos de memória (*memory leaks*) sob regime contínuo de estresse em produção sem precisar acoplar profiladores externos.

---

### Passo 4: O Arquivo Principal Estruturado: ConnectOSApi.lpr

Agora que a lógica da rota está isolada em sua própria unit, o ponto de entrada principal `src/ConnectOSApi.lpr` atua como um maestro de orquestração limpo, conciso e legível:

```pascal
{======================================================================}
{ Projeto: ConnectOSApi - API RESTful Multi-Tenant Corporativa        }
{ Livro  : Desenvolvimento de APIs REST Modernas com Horse e Lazarus   }
{ Autor  : Mauricio Abreu                                              }
{ Ponto  : Entrada do executavel principal (Daemon / Console)          }
{======================================================================}
program ConnectOSApi;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  SysUtils,
  Classes,
  Horse,
  Horse.Provider.FPHTTP,
  Controllers.Ping;

procedure DoOnListen;
begin
  WriteLn('----------------------------------------------------');
  WriteLn('  CONNECT OS API - INICIALIZADA COM SUCESSO         ');
  WriteLn('  Compilador : Free Pascal ' + {$I %FPCVERSION%});
  WriteLn('  Arquitetura: ' + {$I %FPCTARGETCPU%} + '-' + 
          {$I %FPCTARGETOS%});
  WriteLn('  Ouvindo em : http://0.0.0.0:' + IntToStr(THorse.Port));
  WriteLn('----------------------------------------------------');
  WriteLn('Pressione [CTRL+C] no console para encerrar.');
end;

var
  vPorta: Word;
begin
  { Leitura da porta por variavel de ambiente ou padrao 9000 }
  vPorta := StrToIntDef(GetEnvironmentVariable('PORT'), 9000);
  THorse.Port := vPorta;

  { Registro dos controladores de rota }
  TControllersPing.Registry;

  { Inicializacao do servidor }
  THorse.Listen(@DoOnListen);
end.
```

---

### Passo 5: O Arquivo de Projeto do Lazarus (ConnectOSApi.lpi)

Para permitir que o projeto seja aberto, editado e depurado visualmente na IDE do Lazarus por desenvolvedores que preferem a interface gráfica, criamos o arquivo de projeto `src/ConnectOSApi.lpi`. 

O segredo de portabilidade do `.lpi` reside em utilizar exclusivamente **caminhos relativos** com barras normais `/` e macros internas do compilador como `$(ProjOutDir)`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CONFIG>
  <ProjectOptions>
    <Version Value="12"/>
    <General>
      <Flags>
        <MainUnitHasCreateFormStatements Value="False"/>
        <MainUnitHasTitleStatement Value="False"/>
        <MainUnitHasScaledStatement Value="False"/>
      </Flags>
      <SessionStorage Value="InProjectDir"/>
      <Title Value="ConnectOSApi"/>
      <UseAppBundle Value="False"/>
      <ResourceType Value="res"/>
    </General>
    <BuildModes>
      <Item Name="Default" Default="True"/>
      <Item Name="Debug">
        <CompilerOptions>
          <Version Value="11"/>
          <Target>
            <Filename Value="../../bin/ConnectOSApi"/>
          </Target>
          <SearchPaths>
            <IncludeFiles Value="$(ProjOutDir);
              ../../modules/horse/src"/>
            <OtherUnitFiles Value="Controllers;Core;
              Interfaces;Models;DTOs;Repositories;
              Services;../../modules/horse/src"/>
            <UnitOutputDirectory 
              Value="../../lib/$(TargetCPU)-$(TargetOS)"/>
          </SearchPaths>
          <Parsing>
            <SyntaxOptions>
              <SyntaxMode Value="objfpc"/>
            </SyntaxOptions>
          </Parsing>
          <Linking>
            <Debugging>
              <DebugInfoType Value="dsDwarf3"/>
              <UseHeaptrc Value="True"/>
              <TrashVariables Value="True"/>
            </Debugging>
          </Linking>
        </CompilerOptions>
      </Item>
      <Item Name="Release">
        <CompilerOptions>
          <Version Value="11"/>
          <Target>
            <Filename Value="../../bin/ConnectOSApi"/>
          </Target>
          <SearchPaths>
            <IncludeFiles Value="$(ProjOutDir);
              ../../modules/horse/src"/>
            <OtherUnitFiles Value="Controllers;Core;
              Interfaces;Models;DTOs;Repositories;
              Services;../../modules/horse/src"/>
            <UnitOutputDirectory 
              Value="../../lib/$(TargetCPU)-$(TargetOS)"/>
          </SearchPaths>
          <CodeGeneration>
            <SmartLinkUnit Value="True"/>
            <Optimizations>
              <OptimizationLevel Value="3"/>
            </Optimizations>
          </CodeGeneration>
          <Linking>
            <Debugging>
              <GenerateDebugInfo Value="False"/>
              <StripSymbols Value="True"/>
            </Debugging>
            <LinkSmart Value="True"/>
          </Linking>
        </CompilerOptions>
      </Item>
    </BuildModes>
    <Units>
      <Unit>
        <Filename Value="ConnectOSApi.lpr"/>
        <IsPartOfProject Value="True"/>
      </Unit>
      <Unit>
        <Filename Value="Controllers/Controllers.Ping.pas"/>
        <IsPartOfProject Value="True"/>
      </Unit>
    </Units>
  </ProjectOptions>
  <CompilerOptions>
    <Version Value="11"/>
    <Target>
      <Filename Value="../../bin/ConnectOSApi"/>
    </Target>
    <SearchPaths>
      <IncludeFiles Value="$(ProjOutDir);
        ../../modules/horse/src"/>
      <OtherUnitFiles Value="Controllers;Core;
        Interfaces;Models;DTOs;Repositories;
        Services;../../modules/horse/src"/>
      <UnitOutputDirectory 
        Value="../../lib/$(TargetCPU)-$(TargetOS)"/>
    </SearchPaths>
  </CompilerOptions>
</CONFIG>
```

---

## 4. TESTANDO O ENDPOINT

Com o projeto estruturado e modularizado, podemos compilar a aplicação diretamente via linha de comando ou pela IDE. Vamos testar a compilação e a validação do endpoint.

### Compilando via Linha de Comando no Linux ou Windows

Você pode compilar o projeto utilizando o utilitário `lazbuild` ou invocando diretamente o compilador `fpc`:

```bash
# Compilacao via lazbuild
lazbuild --build-mode=Release src/ConnectOSApi.lpi

# Ou compilacao direta ultrarrapida via fpc:
fpc -Mobjfpc -Sh -O3 -Xs -XX \
    -Fu"src/Controllers" \
    -Fu"../../modules/horse/src" \
    -FE"../../bin" \
    src/ConnectOSApi.lpr
```

Inicie o servidor no terminal:
```bash
./bin/ConnectOSApi
```

---

### Teste 1: Validação do Endpoint /ping

Dispare uma chamada `curl` para certificar-se de que a rota mapeada em `Controllers.Ping.pas` responde adequadamente:

```bash
curl -i http://localhost:9000/ping
```

**Resposta do Servidor:**

```http
HTTP/1.1 200 OK
Content-Type: text/plain; charset=utf-8
Content-Length: 68
Date: Mon, 23 Nov 2026 11:45:00 GMT
Server: fphttpserver

{"status":"pong","servico":"ConnectOSApi",
 "timestamp":"2026-11-23T11:45:00.123Z"}
```

---

### Teste 2: Inspeção de Telemetria de Memória (/api/v1/metrics)

Invoque o endpoint de métricas operacionais:

```bash
curl -s http://localhost:9000/api/v1/metrics | jq .
```

*(Caso não possua o utilitário `jq` instalado, execute apenas `curl -s http://localhost:9000/api/v1/metrics`)*

**Payload JSON Retornado:**

```json
{
  "servico": "ConnectOSApi",
  "fpc_version": "3.2.2",
  "target_cpu": "x86_64",
  "target_os": "linux",
  "heap_usado_bytes": 1425808,
  "heap_alocado_bytes": 2097152,
  "heap_maximo_bytes": 2097152
}
```

Observe a precisão dos dados: o servidor compilado com o FPC está operando consumindo apenas **1,42 MB** de heap real (`heap_usado_bytes`), tendo alocado apenas 2 MB do sistema operacional (`heap_alocado_bytes`). Nenhuma outra tecnologia de backend atual entrega essa eficiência com inicialização inferior a 10 milissegundos.

---

## 5. ARMADILHAS COMUNS E TROUBLESHOOTING NO FPC/LAZARUS

Mesmo com um setup profissional baseado em Boss, algumas armadilhas clássicas de configuração de ambiente podem surgir.

---

### Armadilha 1: Erro Fatal "Can't find unit Horse"

**Sintoma:** Ao compilar o projeto pela linha de comando ou pela IDE Lazarus, o processo falha imediatamente com a mensagem:

```text
ConnectOSApi.lpr(16,3) Fatal: Can't find unit Horse used by ConnectOSApi
```

**Causa Raiz:** O compilador FPC não sabe onde os arquivos-fonte do Horse estão armazenados. Isso ocorre quando o comando `boss install` ainda não foi executado (a pasta `modules/` não existe) ou o caminho `-Fumodules/horse/src` não foi incluído no arquivo `.lpi` ou nos parâmetros do compilador.

**Solução Definitiva:**
1. Certifique-se de restaurar os pacotes executando `boss install` na raiz do projeto.
2. No Lazarus, acesse **Project** -> **Project Options** -> **Compiler Options** -> **Paths**.
3. No campo **Other unit files (-Fu)**, adicione o caminho relativo:
   `../../modules/horse/src` (ou `modules/horse/src` conforme o diretório base).
4. Salve as opções e recompile o projeto (`Shift + F9`).

---

### Armadilha 2: Inconsistência de Separadores de Diretório (Windows vs. Linux)

**Sintoma:** O projeto compila perfeitamente na máquina de desenvolvimento com Windows 11, mas falha ao ser compilado em uma esteira CI/CD no Linux Ubuntu com mensagens de arquivo não encontrado.

**Causa Raiz:** Uso de barras invertidas (`\`) manuais na cláusula `uses` ou nas opções do compilador:

```pascal
{ EQUIVOCO GRAVE: Quebra a portabilidade no Linux }
uses
  Controllers\Controllers.Ping;
```

O Linux possui sistema de arquivos sensível a maiúsculas e minúsculas (*case-sensitive*) e reconhece estritamente a barra normal (`/`) como separador de diretórios. No Windows, o compilador FPC aceita tanto `/` quanto `\`.

**Solução:** Sempre adicione os diretórios à lista de busca (`-Fu`) do compilador e declare na cláusula `uses` apenas o nome formal da unit (`uses Controllers.Ping;`), mantendo sempre a barra normal (`/`) em qualquer arquivo de configuração.

---

### Armadilha 3: Comitar a Pasta modules/ no Repositório Git

**Sintoma:** O repositório Git atinge centenas de megabytes rapidamente, gerando conflitos insolúveis de merge toda vez que uma dependência é atualizada por outro desenvolvedor.

**Causa Raiz:** Esquecer de criar o `.gitignore` antes de executar o primeiro `git add .`, permitindo que os submódulos da pasta `modules/` sejam comitados.

**Solução:** Remova a pasta `modules/` do índice do Git mantendo os arquivos locais intactos:

```bash
git rm -r --cached modules/
git commit -m "chore: remove pasta modules do versionamento Git"
```

---

## 6. RESUMO EXECUTIVO E CHECKLIST DE REVISÃO

### Tabela de Comparação: Gerenciamento Tradicional vs. Boss CLI

| Dimensão | Modelo Tradicional (Manual / .lpk) | Modelo Profissional (Boss CLI + FPC) |
| :--- | :--- | :--- |
| **Declaração** | Nenhuma (pastas soltas na máquina) | Formalizada e auditável em `boss.json` |
| **Travamento de Versão**| Inexistente (risco constante de quebra) | Imutável e criptográfico em `boss.lock` |
| **CI/CD Headless** | Complexo (exige instalar pacotes na IDE) | Trivial (`boss install && fpc projeto.lpr`) |
| **Isolamento** | Global (compartilhado na IDE) | Local e estrito por projeto em `modules/` |
| **Portabilidade** | Frequentemente amarrado a paths do Windows | Universal (caminhos relativos e portáveis) |

---

### Checklist de Revisão e Auditoria Técnica

Antes de avançar para o Módulo 03, certifique-se de que o seu setup cumpre integralmente os seguintes requisitos:

- [ ] **Manifestos do Boss:** Os arquivos `boss.json` e `boss.lock` foram criados e estão presentes na raiz do projeto prático.
- [ ] **Configuração do Git:** O arquivo `.gitignore` foi configurado e a pasta `modules/` não está sendo rastreada pelo Git.
- [ ] **Separação de Camadas:** A lógica da rota de telemetria reside em `src/Controllers/Controllers.Ping.pas`, mantendo o `ConnectOSApi.lpr` limpo e focado na orquestração.
- [ ] **Portabilidade do .lpi:** O arquivo `src/ConnectOSApi.lpi` utiliza apenas caminhos relativos e macros do compilador, sem caminhos absolutos atrelados a letras de unidade (ex: `C:\`).
- [ ] **Compilação sem Avisos:** O binário foi compilado tanto em modo Debug quanto em modo Release sem erros ou avisos graves.
- [ ] **Telemetria Funcional:** Os endpoints `/ping` e `/api/v1/metrics` responderam com sucesso via `curl`, comprovando o baixo consumo de memória do heap FPC.

Com a fundação do nosso projeto corporativo formalmente estabelecida, estamos prontos para avançar para o **Módulo 03**, onde mergulharemos a fundo no motor de roteamento avançado, nos verbos HTTP RESTful e na captura de parâmetros complexos.
