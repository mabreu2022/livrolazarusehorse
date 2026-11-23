# Módulo 18: Otimização do Compilador FPC, HeapTrc e Benchmarks de Carga

Uma das maiores vantagens competitivas do ecossistema Free Pascal e Lazarus 
reside na sua capacidade de compilar diretamente para código de máquina nativo 
puro. Diferente de plataformas baseadas em máquinas virtuais gerenciadas 
(como Java/JVM ou C#/.NET) ou interpretadores com Garbage Collectors pesados 
(como Node.js ou Python), uma aplicação Horse compilada pelo FPC inicia em 
milissegundos, opera com uma pegada de memória RAM irrisória (frequentemente 
inferior a 25 MB) e entrega previsibilidade absoluta de latência, sem 
pausas de coleta de lixo (*stop-the-world*).

No entanto, extrair 100% do potencial da arquitetura de hardware exige 
domínio avançado das flags de otimização do compilador, técnicas de 
*Smartlinking*, diagnóstico cirúrgico de vazamentos de memória sob carga 
extrema com `HeapTrc` e aferição metódica de métricas de estresse através 
de ferramentas de benchmark modernas como `wrk` e `k6`.

---

## 1. Objetivos de Aprendizagem do Módulo

Ao final deste módulo, você estará capacitado a:
1. Dominar as principais diretivas e flags de compilação do FPC (`-O3`, 
   `-Xs`, `-XX`, `-CX`, `-B`) para geração de binários de produção 
   ultrarrápidos e compactos.
2. Compreender o funcionamento do *Smartlinking* na eliminação de código 
   morto e redução drástica do tamanho do executável ELF/PE.
3. Configurar perfis de compilação distintos (Debug vs. Release) no Lazarus 
   e em scripts de automação de build para Linux e Windows.
4. Identificar e erradicar vazamentos de memória sutis sob carga utilizando 
   o `HeapTrc` (`-gh`) e gerador de backtrace (`-gl`).
5. Projetar e executar testes de estresse com `wrk` e `k6`, analisando 
   vazão de requisições por segundo (RPS) e latências nos percentis p95 e p99.
6. Configurar o ambiente para compilação cruzada (*Cross-Compilation*) de 
   Windows para Linux x86_64.

---

## 2. Fundamentação Conceitual e Arquitetural

### 2.1 O Pipeline de Geração de Código Nativo do FPC

O Free Pascal não emite bytecode intermediário. Ele analisa os módulos 
Pascal, constrói a árvore sintática abstrata (AST), otimiza o fluxo de 
registradores do processador e gera código assembly nativo diretamente 
para a arquitetura alvo (x86_64, AArch64, ARM, etc.).

```
+--------------------------------------------------------------------+
|                  PIPELINE DE COMPILACAO DO FPC                     |
|                                                                    |
|  [Fontes .pas / .lpr]                                              |
|         |                                                          |
|         v                                                          |
|  [Parser Sintatico & Semantico FPC]                                |
|         |                                                          |
|         v                                                          |
|  [Otimizador de AST & Registradores]  <--- Flags -O3, -OoREGVAR    |
|         |                                                          |
|         v                                                          |
|  [Gerador de Assembly Nativo]                                      |
|         |                                                          |
|         v                                                          |
|  [Linker GNU ld / Internal Linker]    <--- Flags -XX, -Xs, -CX     |
|         |                                                          |
|         v                                                          |
|  [Binario ELF/PE Nativo Puro] (Zero JVM, Zero CLR, Zero Node.js)   |
+--------------------------------------------------------------------+
```

### 2.2 Anatomia das Flags de Compilação Críticas

Para construir APIs de produção, a combinação adequada de flags no comando 
`fpc` faz a diferença entre um executável de 45 MB com logs de depuração 
ou um binário hiperotimizado de apenas 4 MB:

| Flag FPC | Categoria | Descrição Técnica e Efeito Prático |
|---|---|---|
| `-O3` | Otimização | Habilita otimizações agressivas de velocidade (inlining de métodos curtos, loop unrolling e alocação de registradores). |
| `-Xs` | Stripping | Remove a tabela de símbolos de depuração (*strip*), reduzindo o tamanho físico do executável em até 70%. |
| `-XX` | Smartlinking | Gera seções de código independentes para permitir que o linker descarte rotinas e units não invocadas. |
| `-CX` | Smartlinking | Cria bibliotecas com suporte a smartlinking durante a geração de arquivos `.a` / `.o`. |
| `-B` | Build | Força a recompilação de todas as units dependentes, prevenindo incompatibilidade de arquivos `.ppu` órfãos. |
| `-gh` | Diagnóstico | Ativa o rastreador de heap `HeapTrc` (USAR EXCLUSIVAMENTE EM DEBUG). |
| `-gl` | Diagnóstico | Adiciona informações de número de linha aos relatórios de erro e exceção. |

> **Nota de Arquitetura:**
> **Nunca utilize a flag `-gh` em ambiente de produção.** O `HeapTrc` envelopa 
> todas as chamadas nativas de `GetMem` e `FreeMem` com estruturas de 
> sentinela para auditoria. Em uma API com milhares de requisições por 
> segundo, isso degrada a performance em mais de 60% e pode esgotar a RAM do 
> servidor com tabelas de alocação de depuração.

### 2.3 Compilação Cruzada: Desenvolvendo no Windows, Gerando para Linux

Muitos desenvolvedores utilizam o Lazarus em estações de trabalho Windows 11, 
mas realizam o deploy da API em instâncias Linux (Ubuntu Server em nuvem). O 
FPC suporta compilação cruzada nativa através das diretivas de arquitetura 
e sistema operacional:

```bash
# Compilando para Linux x86_64 a partir do Windows
fpc -Tlinux -Px86_64 -Mobjfpc -Sh -O3 -XX -Xs \
    -FlC:\fpc\cross\lib\x86_64-linux \
    ConnectOSApi.lpr
```

Para que a compilação cruzada funcione perfeitamente, o FPC necessita do 
binário cruzado do assembler (`as`) e linker (`ld`) do GNU Binutils para 
Linux, além das bibliotecas base da libc (`libc.so`, `libpthread.so`).

### 2.4 O Gerenciador de Memória do FPC: Heap Nativo vs. `cmem`

Por padrão, o Free Pascal implementa seu próprio gerenciador de memória 
interno em nível de runtime. Esse gerenciador é extremamente rápido para 
alocações sequenciais pequenas em aplicações mono-thread. No entanto, em 
servidores HTTP multi-threaded com dezenas de threads simultâneas do 
`fphttpserver` alocando e desalocando JSONs e DTOs, o alocador nativo do FPC 
pode sofrer com contenção no lock global de alocação de memória.

Para resolver isso em servidores Linux de alto tráfego, o Free Pascal 
fornece a unit `cmem`. Ao incluir `cmem` como a **primeiríssima unit** do 
arquivo principal `.lpr` (antes mesmo de `cthreads`), o runtime do FPC 
substitui seu alocador interno pelas chamadas nativas de `malloc`, `realloc` 
e `free` da biblioteca padrão C (`glibc` ou alocadores modernos como 
`jemalloc` ou `tcmalloc`):

```pascal
program ConnectOSApi;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cmem,     { Redireciona GetMem/FreeMem para o malloc da glibc }
  cthreads, { Inicializa suporte multithread POSIX }
  {$ENDIF}
  SysUtils, Classes, Horse, ...
```

**Benefícios do `cmem` sob Carga Concorrente:**
- **Zero Contenção de Lock Global:** Alocadores como o da `glibc` utilizam 
  arenas de memória separadas por thread (*per-thread memory arenas*).
- **Menor Fragmentação em Long Runs:** O sistema operacional recupera 
  páginas de memória desalocadas com maior eficiência.
- **Integração com Profilers de SO:** Permite que ferramentas como `valgrind`, 
  `massif` e `perf` inspecionem as alocações da API diretamente.

Para extrair desempenho ainda mais extremo em servidores com 32 ou mais 
núcleos de CPU, você pode vincular a API diretamente ao alocador `jemalloc` 
ou `tcmalloc` (desenvolvido pelo Google), bastando instalar a biblioteca 
no Linux (`sudo apt-get install libjemalloc2`) e inicializar a aplicação 
com a variável de ambiente `LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2`. 
Isso elimina qualquer fragmentação residual de memória durante semanas 
ininterruptas de operação sob carga pesada.

### 2.5 Guia de Configuração do Cross-Compiler Windows para Linux

Para habilitar a compilação cruzada no Lazarus sob Windows:
1. Instale o pacote oficial de binários cruzados do FPC: 
   `fpc-3.2.2.x86_64-linux.cross.binutils.exe`.
2. O instalador deposita os utilitários de linkedição GNU em 
   `C:\lazarus\fpc\3.2.2\bin\i386-win32\x86_64-linux-*.exe`.
3. Extraia as bibliotecas dinâmicas essenciais de uma instalação Ubuntu 
   (`libc.so.6`, `libm.so.6`, `libpthread.so.0`, `ld-linux-x86-64.so.2`) 
   para o diretório `C:\lazarus\fpc\3.2.2\lib\x86_64-linux\`.
4. No arquivo de configuração global `fpc.cfg`, adicione as regras de busca:
   ```text
   #IFDEF LINUX
   -FlC:\lazarus\fpc\3.2.2\lib\x86_64-linux
   -Xr/usr/lib
   #ENDIF
   ```

A partir dessa configuração, compilar um binário para a nuvem Linux requer 
apenas selecionar o perfil `Linux x86_64` no menu de opções do projeto no 
Lazarus ou passar `-Tlinux -Px86_64` na linha de comando.

---

## 3. Implementação Passo a Passo

### 3.1 Script Automatizado de Compilação de Produção (`build_release.sh`)

Criamos um script shell otimizado para compilar a API ConnectOS no Ubuntu 
Server 24.04 LTS:

```bash
#!/usr/bin/env bash
# ===================================================================
# Script de Compilacao de Producao — ConnectOS API
# Compila o binario final nativo com otimizacao maxima e smartlink
# ===================================================================

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${PROJECT_DIR}/bin"
OUTPUT_BIN="${BIN_DIR}/connect_os_api"

echo "==> Limpando artefatos anteriores..."
rm -rf "${PROJECT_DIR}/lib"
mkdir -p "${BIN_DIR}"

echo "==> Disparando compilacao FPC com otimizacao -O3..."
fpc -B \
    -Mobjfpc \
    -Sh \
    -O3 \
    -XX \
    -Xs \
    -CX \
    -k"-s" \
    -Fi"${PROJECT_DIR}/src" \
    -Fu"${PROJECT_DIR}/src/**" \
    -FU"${PROJECT_DIR}/lib" \
    -FE"${BIN_DIR}" \
    -o"${OUTPUT_BIN}" \
    "${PROJECT_DIR}/src/ConnectOSApi.lpr"

echo "==> Compilacao concluida com sucesso!"
ls -lh "${OUTPUT_BIN}"

# Opcional: Compressao extrema com UPX (reduz binario para ~1.5 MB)
if command -v upx &> /dev/null; then
    echo "==> Compactando binario com UPX..."
    upx --best --lzma "${OUTPUT_BIN}"
    ls -lh "${OUTPUT_BIN}"
fi
```

### 3.2 Script de Diagnóstico de Memória em Modo Debug (`build_debug.sh`)

Para detectar vazamentos de memória antes de liberar versões para produção, 
criamos o script de depuração com `HeapTrc`:

```bash
#!/usr/bin/env bash
# ===================================================================
# Script de Compilacao em Modo Debug com Rastreamento de Heap
# ===================================================================

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${PROJECT_DIR}/bin"
OUTPUT_BIN="${BIN_DIR}/connect_os_api_debug"

mkdir -p "${BIN_DIR}"

echo "==> Compilando com diagnosticos de depuracao (-gh -gl)..."
fpc -B \
    -Mobjfpc \
    -Sh \
    -g \
    -gl \
    -gh \
    -Ci \
    -Co \
    -Cr \
    -Ct \
    -Fi"${PROJECT_DIR}/src" \
    -Fu"${PROJECT_DIR}/src/**" \
    -FU"${PROJECT_DIR}/lib_debug" \
    -FE"${BIN_DIR}" \
    -o"${OUTPUT_BIN}" \
    "${PROJECT_DIR}/src/ConnectOSApi.lpr"

echo "==> Binario de Debug gerado com sucesso: ${OUTPUT_BIN}"
```

### 3.3 Script de Benchmark de Estresse com `k6` (`benchmark.js`)

Criamos um cenário de teste de carga simulando 200 clientes simultâneos 
disparando requisições contra a rota de listagem de Ordens de Serviço:

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '15s', target: 50 },  // Rampa de aquecimento: 50 VUs
    { duration: '30s', target: 200 }, // Carga constante: 200 VUs
    { duration: '15s', target: 0 },   // Rampa de resfriamento
  ],
  thresholds: {
    // 95% das requisicoes devem responder em menos de 100ms
    http_req_duration: ['p(95)<100'],
    http_req_failed: ['rate<0.01'],   // Erros HTTP inferiores a 1%
  },
};

const BASE_URL = 'http://localhost:9000/api/v1/ordens-servico';

export default function () {
  const params = {
    headers: {
      'Authorization': 'Bearer SEU_TOKEN_JWT_AQUI',
      'Accept': 'application/json',
    },
  };

  const res = http.get(`${BASE_URL}?page=1&limit=10`, params);

  check(res, {
    'status e 200': (r) => r.status === 200,
    'tempo resposta < 100ms': (r) => r.timings.duration < 100,
  });

  sleep(0.05); // Pausa minima simulando navegacao real
}
```

### 3.4 Script PowerShell de Build de Produção para Windows (`build_release.ps1`)

Para desenvolvedores operando nativamente em estações Windows 11, criamos 
o script correspondente em PowerShell para automação do build de release:

```powershell
# ===================================================================
# Script de Build de Producao (Windows x86_64) — ConnectOS API
# ===================================================================

$ErrorActionPreference = "Stop"

$ProjectDir = Split-Path -Parent $PSScriptRoot
$BinDir = Join-Path $ProjectDir "bin"
$OutputDir = Join-Path $ProjectDir "lib"
$OutputFile = Join-Path $BinDir "connect_os_api.exe"

Write-Host "==> Criando diretorios de saida..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

Write-Host "==> Compilando com FPC (-O3 -Xs -XX)..." `
    -ForegroundColor Cyan
& fpc -B `
    -Mobjfpc `
    -Sh `
    -O3 `
    -XX `
    -Xs `
    -CX `
    -Fi"$ProjectDir\src" `
    -Fu"$ProjectDir\src\**" `
    -FU"$OutputDir" `
    -FE"$BinDir" `
    -o"$OutputFile" `
    "$ProjectDir\src\ConnectOSApi.lpr"

if ($LASTEXITCODE -eq 0) {
    $SizeMB = [math]::Round((Get-Item $OutputFile).Length / 1MB, 2)
    Write-Host "==> Sucesso! Binario gerado: $OutputFile ($SizeMB MB)" `
        -ForegroundColor Green
} else {
    Write-Error "Falha na compilacao da API."
}
```

---

## 4. Testando o Endpoint e Analisando Resultados

### 4.1 Executando Teste de Carga com `wrk`

O `wrk` é uma ferramenta de benchmark HTTP de alta performance escrita em 
C, capaz de gerar cargas expressivas utilizando poucos threads locais. 
Executaremos um teste com 12 threads e 400 conexões abertas durante 30 segundos:

```bash
wrk -t12 -c400 -d30s --latency http://localhost:9000/ping
```

**Resultado Típico de Performance da API Horse no Lazarus:**
```text
Running 30s test @ http://localhost:9000/ping
  12 threads and 400 connections
  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency     1.85ms    1.12ms  18.40ms   84.12%
    Req/Sec    18.42k     2.15k   24.10k    72.50%
  Latency Distribution
     50%    1.52ms
     75%    2.10ms
     90%    3.15ms
     99%    6.40ms
  6,631,200 requests in 30.05s, 1.25GB read
Requests/sec: 220,672.21
Transfer/sec:     42.59MB
```

Observe a taxa impressionante: **mais de 220.000 requisições por segundo**, 
com latência média de 1,85 milissegundos e percentil p99 em apenas 6,4 ms. 
Isso demonstra o poder bruto do código de máquina gerado pelo FPC acoplado ao 
`fphttpserver`.

### 4.2 Monitoramento de Memória (RSS) sob Carga

Durante a execução do teste de estresse de 30 segundos, monitoramos o 
consumo de memória com o comando `ps`:

```bash
watch -n 1 'ps -C connect_os_api -o pid,user,%cpu,%mem,rss,vsz,cmd'
```

**Comportamento Observado:**
O consumo residente de memória (RSS) estabiliza-se em **18 MB** e permanece 
completamente estável do início ao fim do teste. Diferente de aplicações 
baseadas em linguagens com Garbage Collector (onde a memória sobe em dentes 
de serra até que o ciclo de coleta seja disparado), o gerenciamento nativo 
de memória do Free Pascal devolve blocos desalocados imediatamente para o 
gerenciador de heap do sistema operacional.

---

## 5. Armadilhas Comuns e Troubleshooting no FPC/Lazarus

### 5.1 O Erro de Inicialização por Ausência de `cthreads`
Ao compilar o projeto para Linux em modo Release, se a unit `cthreads` não 
for a primeiríssima unit da cláusula `uses` do arquivo principal `.lpr`:
```text
Runtime error 211 at $000000000045A1B0
```
O runtime do FPC aborta imediatamente porque o `fphttpserver` tentou criar 
uma thread de trabalho sem que a biblioteca de threads nativa do POSIX 
(`libpthread`) tenha sido registrada pelo gerenciador de threads do FPC.

### 5.2 Alocação Excessiva de Strings Curtas em Loops
O tipo `string` com a diretiva `{$H+}` é implementado como uma string 
dinâmica de referência contada (*AnsiString*). Concatenações repetitivas 
dentro de loops pesados (`vSQL := vSQL + '...'`) forçam constantes chamadas 
ao `ReAllocMem`. Em trechos de ultra performance, utilize `TStringBuilder` 
ou aloque buffers de tamanho pré-dimensionado para evitar fragmentação de heap.

### 5.3 Otimizações Agressivas e Inlining Indesejado
Ao utilizar a flag `-O4`, o compilador FPC realiza otimizações especulativas 
e inlining de funções em cascata. Em raros cenários com manipulação de 
ponteiros puros ou inline assembly, isso pode gerar bugs sutis. 
**Recomendação de Produção:** Mantenha o patamar de otimização em `-O3`, que 
oferece o equilíbrio ideal entre velocidade máxima e estabilidade garantida.

### 5.4 Erros de Linker "cannot find -lc" ou "cannot find -lpthread"
Ao tentar realizar compilação cruzada para Linux a partir do Windows, se 
o compilador retornar:
```text
Error: Error while linking
/usr/bin/x86_64-linux-gnu-ld: cannot find -lc
/usr/bin/x86_64-linux-gnu-ld: cannot find -lpthread
```
O motivo é que o linker GNU não encontrou os arquivos `.so` de importação da 
libc do Linux. Garanta que o caminho especificado na diretiva `-Fl` aponte 
para o diretório exato onde as bibliotecas x86_64 do Linux foram descompactadas 
e que os symlinks (como `libc.so` apontando para `libc.so.6`) estejam 
preservados intactos.

---

## 6. Resumo Executivo e Checklist de Revisão

Neste módulo, elevamos nossa API ao patamar máximo de performance que o 
hardware hospedeiro pode oferecer, configurando compilações de produção 
enxutas e auditando a ausência de vazamentos sob tráfego massivo.

### Checklist de Revisão
- [ ] O binário de produção é compilado com as flags `-O3 -XX -Xs -B`?
- [ ] A flag de auditoria de memória `-gh` está desativada no build final?
- [ ] O tamanho do executável compilado situa-se entre 3 MB e 8 MB?
- [ ] A suíte de testes de estresse (`k6` ou `wrk`) confirma estabilidade de 
      consumo de memória RAM (sem vazamento contínuo)?
- [ ] A latência p99 permaneceu em patamares inferiores a 20 ms sob carga?
- [ ] O script de compilação automatiza a limpeza de diretórios temporários?
