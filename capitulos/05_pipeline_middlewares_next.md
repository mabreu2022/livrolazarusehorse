# MÓDULO 05: O PIPELINE DE MIDDLEWARES E O DELEGADO TNEXTPROC

---

## 1. OBJETIVOS DE APRENDIZAGEM DO MÓDULO

Ao final deste módulo, você será capaz de:

1. Compreender o padrão comportamental de projeto **Chain of Responsibility** aplicado à arquitetura de processamento HTTP do Horse.
2. Dominar a assinatura e o ciclo de vida do delegado **`TNextProc`**, identificando os momentos exatos de interceptação pré-processamento (*before*) e pós-processamento (*after*).
3. Projetar e construir um middleware corporativo de rastreabilidade distribuída (**Correlation-ID**) injetando identificadores únicos universais (UUID).
4. Desenvolver um middleware de auditoria e telemetria (**HTTP Request Logger**) calculando o tempo de resposta em microssegundos sem degradar a vazão da API.
5. Implementar um middleware thread-safe de controle de vazão (**Rate Limiting**) em memória, aplicando sincronização atômica com `TCriticalSection` e emitindo respostas HTTP `429 Too Many Requests`.

---

## 2. FUNDAMENTAÇÃO CONCEITUAL E ARQUITETURAL

Nas arquiteturas de software modernas, uma requisição HTTP raramente transita diretamente do socket de rede para a regra de negócio da rota. Antes que um controlador manipule os dados, a requisição deve ser auditada, autenticada, sanitizada, validada contra limites de tráfego e ter seu contexto de rastreabilidade devidamente inicializado. De forma análoga, antes que a resposta seja despachada ao cliente, cabeçalhos de segurança, compressão de dados e logs de encerramento precisam ser adicionados.

Acoplar essas tarefas utilitárias e transversais (*cross-cutting concerns*) dentro de cada controlador gera duplicação maciça de código, viola o Princípio da Responsabilidade Única (SRP do SOLID) e torna a manutenção inviável.

Para resolver esse problema de forma elegante, o Horse adota o padrão **Pipeline de Middlewares**, consubstanciado no padrão clássico de projeto **Chain of Responsibility** (GoF).

```
[ REQUISIÇÃO TCP ENTRANTE ]
            |
            v
+-----------------------+
|  Middleware 1: CORS   |  (Trata Preflight OPTIONS)
+-----------------------+
            |  Next()
            v
+-----------------------+
| Middleware 2: Tracing |  (Gera ou preserva X-Correlation-ID)
+-----------------------+
            |  Next()
            v
+-----------------------+
| Middleware 3: RateLmt |  (Valida consumo por IP/Tenant -> 429?)
+-----------------------+
            |  Next()
            v
+-----------------------+
| Middleware 4: Logger  |  (Inicia cronômetro T0)
+-----------------------+
            |  Next()
            v
+=======================+
|   ROTA / CONTROLLER   |  (Executa a Regra de Negócio / Banco)
+=======================+
            |  Retorno do Next()
            v
+-----------------------+
| Middleware 4: Logger  |  (Calcula DeltaT e emite Log estruturado)
+-----------------------+
            |  Retorno do Next()
            v
[ RESPOSTA TCP AO CLIENTE ]
```

### A Assinatura de um Middleware no Horse e o Tipo TNextProc

No Free Pascal, o Horse define a assinatura de qualquer elo de middleware através do tipo procedimental `THorseCallback`:

```pascal
type
  TNextProc = procedure;
  THorseCallback = procedure(Req: THorseRequest; Res: THorseResponse; 
    Next: TNextProc);
```

Observe a presença do terceiro argumento: `Next: TNextProc`. Trata-se de um ponteiro procedimental delegado que aponta para o próximo middleware da cadeia (ou para o controlador final da rota).

O fluxo de controle dentro de um middleware divide-se em três etapas lógicas estritas:

1. **Fase Before (Pré-execução):** Código executado **antes** da invocação de `Next()`. É o espaço onde o middleware inspeciona a requisição, valida cabeçalhos, inicia contadores e aplica regras de segurança.
2. **Transferência de Controle (`Next()`):** A chamada ao método `Next()` transfere imediatamente a linha de execução para o próximo elo da corrente. A execução da thread corrente entra na pilha do próximo componente e permanece em espera até que ele retorne.
3. **Fase After (Pós-execução):** Código posicionado imediatamente **após** a chamada `Next()`. É executado no caminho de volta da resposta, permitindo modificar cabeçalhos de saída, auditar o código de status HTTP resultante (`Res.Status`) e computar a latência total da chamada.

### O Mecanismo de Curto-Circuito (Short-Circuiting)

Uma das maiores forças do pipeline é a capacidade de interromper o fluxo precocemente. Se um middleware constatar que a requisição é inválida (por exemplo: um token expirado, ausência de cabeçalho obrigatório ou esgotamento da cota de requisições no Rate Limiter), o middleware simplesmente **NÃO invoca `Next()`**.

Ao preencher o objeto `Res` e omitir a chamada `Next()`, a cadeia é imediatamente abortada: nenhum middleware subsequente é chamado e o controlador da rota sequer é instanciado. O Horse pega a resposta montada pelo middleware sentinela e a devolve diretamente ao cliente de rede, economizando ciclos preciosos de CPU e consultas desnecessárias ao banco de dados Firebird.

> **Nota de Arquitetura:**  
> A ordem em que os middlewares são registrados através de `THorse.Use(...)` dita rigorosamente a ordem em que serão executados na fase *Before* e a ordem inversa na fase *After*. Um middleware de captura global de exceções, por exemplo, deve ser sempre o **primeiríssimo** a ser registrado no pipeline, para que possa encapsular toda a execução subsequente em um bloco `try..except` protetor.

### Concorrência e Sincronização em Middlewares no FPC

Como vimos no Bloco I, o driver `fphttpserver` aloca uma thread de sistema operacional para cada conexão HTTP aberta. Isso significa que, se 1.000 clientes estiverem requisitando a API simultaneamente, o código do mesmo middleware estará sendo executado por 1.000 threads distintas ao mesmo tempo.

Para middlewares puramente stateless (como Correlation-ID e Logger de console), isso não introduz atrito, pois cada thread opera exclusivamente sobre suas próprias variáveis locais e sobre as instâncias de `Req` e `Res` atreladas àquela requisição.

Contudo, para middlewares que mantêm **estado compartilhado em memória** — como um Rate Limiter que contabiliza requisições por endereço IP —, múltiplas threads tentarão ler e escrever na mesma tabela hash ou dicionário em memória. No Free Pascal, qualquer mutação concorrente de memória compartilhada sem sincronização resulta em corrupção imediata de memória (*SIGSEGV*).

Para garantir segurança absoluta de concorrência (*thread-safety*), utilizaremos o objeto **`TCriticalSection`** da unit `syncobjs`, assegurando exclusão mútua atômica em trechos críticos com overhead de microssegundos.

---

## 3. IMPLEMENTAÇÃO PASSO A PASSO

Construiremos agora três middlewares corporativos de alto nível para integrar à nossa infraestrutura **ConnectOSApi**:
1. `Middlewares.CorrelationId.pas`: Rastreabilidade distribuída e injeção de UUID.
2. `Middlewares.Logger.pas`: Log estruturado de auditoria com cálculo de latência em milissegundos.
3. `Middlewares.RateLimit.pas`: Limitador de taxa em memória por endereço IP.

### Passo 1: Middleware de Correlation-ID (Rastreabilidade Distribuída)

Crie a unit `src/Core/Middlewares.CorrelationId.pas`:

```pascal
{======================================================================}
{ Projeto: ConnectOSApi - API de Gestao e Faturamento Multi-Tenant     }
{ Unit   : Middlewares.CorrelationId                                   }
{ Papel  : Gerenciamento e propagacao de cabecalho X-Correlation-ID    }
{======================================================================}
unit Middlewares.CorrelationId;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  Horse;

type
  TMiddlewareCorrelationId = class
  private
    class function GerarUUID: string;
  public
    class procedure Middleware(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
  end;

implementation

{ TMiddlewareCorrelationId }

class function TMiddlewareCorrelationId.GerarUUID: string;
var
  vGUID: TGUID;
begin
  CreateGUID(vGUID);
  { Formata GUID removendo chaves: {XXXXXXXX-XXXX...} -> XXXXXXXX-XXXX }
  Result := LowerCase(Copy(GUIDToString(vGUID), 2, 36));
end;

class procedure TMiddlewareCorrelationId.Middleware(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vCorrelationId: string;
begin
  { 1. Verifica se o cliente ja enviou um Correlation-ID proprio }
  vCorrelationId := Req.Headers.Field('X-Correlation-ID').AsString;

  { 2. Caso nao tenha sido enviado, gera um UUID v4 novo }
  if Trim(vCorrelationId) = '' then
    vCorrelationId := GerarUUID;

  { 3. Injeta o cabecalho na resposta para devolucao ao cliente }
  Res.RawWebResponse.SetCustomHeader('X-Correlation-ID', 
    vCorrelationId);

  { 4. Transfere a execucao para o proximo middleware/rota }
  Next();
end;

end.
```

---

### Passo 2: Middleware de Auditoria e Telemetria HTTP (Logger)

Crie a unit `src/Core/Middlewares.Logger.pas`. Observe a captura precisa do tempo antes e depois da invocação de `Next()`:

```pascal
{======================================================================}
{ Projeto: ConnectOSApi - API de Gestao e Faturamento Multi-Tenant     }
{ Unit   : Middlewares.Logger                                          }
{ Papel  : Auditoria estruturada de requisicoes com medicao de tempo   }
{======================================================================}
unit Middlewares.Logger;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  Horse;

type
  TMiddlewareLogger = class
  public
    class procedure Middleware(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
  end;

implementation

{ TMiddlewareLogger }

class procedure TMiddlewareLogger.Middleware(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vInicioMS: QWord;
  vDuracaoMS: QWord;
  vMetodo: string;
  vCaminho: string;
  vIPOrigem: string;
  vCorrelationId: string;
  vStatusHTTP: Integer;
begin
  { FASE BEFORE: Captura metadados da requisicao e marca tempo inicial }
  vInicioMS := GetTickCount64;
  vMetodo := Req.RawWebRequest.Method;
  vCaminho := Req.RawWebRequest.PathInfo;
  vIPOrigem := Req.RawWebRequest.RemoteAddress;

  { PROXIMO ELO: Executa o restante do pipeline e o controlador }
  try
    Next();
  finally
    { FASE AFTER: Executada sempre, mesmo se houver excecao na rota }
    vDuracaoMS := GetTickCount64 - vInicioMS;
    vStatusHTTP := Res.RawWebResponse.Code;
    vCorrelationId := 
      Res.RawWebResponse.GetCustomHeader('X-Correlation-ID');

    { Emissao de log estruturado padronizado no terminal/journalctl }
    WriteLn(Format(
      '[HTTP] %s | %-6s | %-20s | Status: %d | %d ms | CorrID: %s',
      [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now),
       vMetodo,
       vCaminho,
       vStatusHTTP,
       vDuracaoMS,
       vCorrelationId]));
  end;
end;

end.
```

> **Boas Práticas FPC:**  
> O uso de `GetTickCount64` nativo da unit `SysUtils` no Free Pascal garante uma contagem monotônica de tempo em milissegundos sem sofrer com o problema de retrocesso temporal causado por ajustes automáticos de relógio do sistema operacional (NTP) ou virada de dia. Além disso, encapsular a chamada `Next()` dentro de um bloco `try..finally` garante que o tempo de resposta e o log de auditoria sejam emitidos mesmo que a rota gere uma exceção fatal não tratada.

---

### Passo 3: Middleware de Rate Limiting em Memória (Thread-Safe)

Para proteger a API contra ataques de negação de serviço (DoS) e abusos de tráfego, criaremos um limitador de taxa (*Rate Limiter*) baseado no algoritmo de janela fixa de tempo (*Fixed Window Counter*). 

A unit `src/Core/Middlewares.RateLimit.pas` utiliza um array dinâmico em memória protegido por uma `TCriticalSection` global para rastrear as requisições por endereço IP:

```pascal
{======================================================================}
{ Projeto: ConnectOSApi - API de Gestao e Faturamento Multi-Tenant     }
{ Unit   : Middlewares.RateLimit                                       }
{ Papel  : Limitador de taxa de chamadas por IP thread-safe           }
{======================================================================}
unit Middlewares.RateLimit;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  syncobjs,
  Horse,
  Core.ProblemDetails;

type
  { Registro para contagem de requisicoes por IP em memoria }
  TRateLimitEntry = record
    IP: string;
    Contador: Integer;
    JanelaInicio: QWord;
  end;

  TMiddlewareRateLimit = class
  private
    class var FSection: TCriticalSection;
    class var FTabela: array of TRateLimitEntry;
    class var FLimiteRequisicoes: Integer;
    class var FJanelaSegundos: Integer;
    class function VerificarELimitar(const AIP: string): Boolean;
  public
    class procedure Configurar(ALimitePorJanela: Integer; 
      AJanelaSegundos: Integer);
    class procedure Middleware(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
    class procedure Inicializar;
    class procedure Finalizar;
  end;

implementation

{ TMiddlewareRateLimit }

class procedure TMiddlewareRateLimit.Inicializar;
begin
  FSection := TCriticalSection.Create;
  SetLength(FTabela, 0);
  FLimiteRequisicoes := 60;  { Padrao: 60 requisicoes }
  FJanelaSegundos := 60;     { a cada 60 segundos }
end;

class procedure TMiddlewareRateLimit.Finalizar;
begin
  FSection.Free;
  SetLength(FTabela, 0);
end;

class procedure TMiddlewareRateLimit.Configurar(
  ALimitePorJanela: Integer; AJanelaSegundos: Integer);
begin
  FLimiteRequisicoes := ALimitePorJanela;
  FJanelaSegundos := AJanelaSegundos;
end;

class function TMiddlewareRateLimit.VerificarELimitar(
  const AIP: string): Boolean;
var
  vAgora: QWord;
  vDeltaSegundos: QWord;
  i: Integer;
  vIndice: Integer;
begin
  Result := True; { True = Permitido, False = Bloqueado (429) }
  vAgora := GetTickCount64;

  FSection.Enter; { BLOQUEIO ATOMICO DE CONCORRENCIA }
  try
    vIndice := -1;
    for i := 0 to High(FTabela) do
    begin
      if FTabela[i].IP = AIP then
      begin
        vIndice := i;
        Break;
      end;
    end;

    { Se o IP ainda nao consta na tabela, cadastra nova entrada }
    if vIndice = -1 then
    begin
      vIndice := Length(FTabela);
      SetLength(FTabela, vIndice + 1);
      FTabela[vIndice].IP := AIP;
      FTabela[vIndice].Contador := 1;
      FTabela[vIndice].JanelaInicio := vAgora;
      Exit(True);
    end;

    { Calcula tempo decorrido desde o inicio da janela deste IP }
    vDeltaSegundos := (vAgora - FTabela[vIndice].JanelaInicio) div 1000;

    if vDeltaSegundos >= QWord(FJanelaSegundos) then
    begin
      { Janela expirou: reinicia contagem para este IP }
      FTabela[vIndice].Contador := 1;
      FTabela[vIndice].JanelaInicio := vAgora;
      Exit(True);
    end;

    { Incrementa contador de chamadas }
    Inc(FTabela[vIndice].Contador);

    if FTabela[vIndice].Contador > FLimiteRequisicoes then
      Result := False; { Estourou o limite! }
  finally
    FSection.Leave; { LIBERACAO ATOMICA }
  end;
end;

class procedure TMiddlewareRateLimit.Middleware(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vIP: string;
begin
  vIP := Req.RawWebRequest.RemoteAddress;
  if Trim(vIP) = '' then
    vIP := '127.0.0.1';

  { Valida requisicao contra o contador em memoria }
  if not VerificarELimitar(vIP) then
  begin
    { CURTO-CIRCUITO: Interrompe a cadeia e emite 429 }
    Res.RawWebResponse.SetCustomHeader('Retry-After', 
      IntToStr(FJanelaSegundos));

    TProblemDetails.CreateNew
      .SetType('https://api.connectos.com/erros/limite-requisicoes')
      .SetTitle('Muitas Requisicoes')
      .SetStatus(429)
      .SetDetail('Limite de taxa excedido. Aguarde antes de retentar.')
      .SetInstance(Req.RawWebRequest.PathInfo)
      .SendTo(Res);
    Exit; { NAO INVOCA NEXT() }
  end;

  { Dentro da cota: prossegue a execucao }
  Next();
end;

initialization
  TMiddlewareRateLimit.Inicializar;

finalization
  TMiddlewareRateLimit.Finalizar;

end.
```

> **Atenção Thread-Safety:**  
> A chamada `FSection.Enter` garante que apenas uma única thread por vez execute a busca e a mutação na tabela `FTabela`. O bloco `try..finally` é obrigatório para invocar `FSection.Leave`. Se uma exceção inesperada ocorresse sem o `finally`, a seção crítica permaneceria bloqueada permanentemente (*deadlock*), paralisando o servidor inteiro para todas as conexões subsequentes.

---

### Passo 4: Conectando os Middlewares no Ponto de Entrada: ConnectOSApi.lpr

Agora conectamos os três middlewares globais utilizando o método `THorse.Use(...)` **antes** do registro dos controladores de rota:

```pascal
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
  Middlewares.CorrelationId,
  Middlewares.Logger,
  Middlewares.RateLimit,
  Controllers.Ping,
  Controllers.Clientes;

procedure DoOnListen;
begin
  WriteLn('----------------------------------------------------');
  WriteLn('  CONNECT OS API - PIPELINE DE MIDDLEWARES ATIVO    ');
  WriteLn('  - Correlation-ID : Ativo (Header X-Correlation-ID)');
  WriteLn('  - Request Logger : Ativo (Console / Journalctl)   ');
  WriteLn('  - Rate Limiter   : Ativo (Cota: 5 req / 10 seg)   ');
  WriteLn('  Ouvindo em : http://0.0.0.0:' + IntToStr(THorse.Port));
  WriteLn('----------------------------------------------------');
end;

var
  vPorta: Word;
begin
  vPorta := StrToIntDef(GetEnvironmentVariable('PORT'), 9000);
  THorse.Port := vPorta;

  { Configuracao do Rate Limiter: 5 chamadas a cada 10 segundos }
  TMiddlewareRateLimit.Configurar(5, 10);

  { REGISTRO DO PIPELINE GLOBAL (ORDEM ESTRITA DE EXECUCAO) }
  THorse.Use(@TMiddlewareCorrelationId.Middleware);
  THorse.Use(@TMiddlewareLogger.Middleware);
  THorse.Use(@TMiddlewareRateLimit.Middleware);

  { REGISTRO DOS CONTROLADORES DE ROTA }
  TControllersPing.Registry;
  TControllersClientes.Registry;

  THorse.Listen(@DoOnListen);
end.
```

---

## 4. TESTANDO O ENDPOINT

Com o pipeline integrado, compilaremos o servidor e auditaremos o funcionamento de cada middleware através de testes práticos de rede.

### Teste 1: Auditoria do Correlation-ID e do Logger Estruturado

Dispare uma chamada de saúde para o endpoint `/ping`:

```bash
curl -i http://localhost:9000/ping
```

**Cabeçalhos de Resposta Recebidos no Terminal:**

```http
HTTP/1.1 200 OK
X-Correlation-ID: 7f8c4e2a-1b3d-4e5f-9a8b-0c1d2e3f4a5b
Content-Type: text/plain; charset=utf-8
Content-Length: 68

{"status":"pong","servico":"ConnectOSApi",
 "timestamp":"2026-11-23T12:00:00.123Z"}
```

**Log Estruturado Emitido no Console do Servidor pelo Middleware de Log:**

```text
[HTTP] 2026-11-23 12:00:00 | GET    | /ping
Status: 200 | 1 ms | CorrID: 7f8c4e2a-1b3d-4e5f-9a8b-0c1d2e3f4a5b
```

Observe a precisão da integração:
1. O servidor gerou dinamicamente um UUID e o anexou no cabeçalho de resposta `X-Correlation-ID`.
2. O logger interceptou a finalização da chamada no bloco `finally`, mediu com exatidão a latência de execução (**1 milissegundo**) e vinculou o mesmo `CorrID` no log de console.

Agora, envie uma chamada informando um Correlation-ID customizado:

```bash
curl -i -H "X-Correlation-ID: transacao-externa-999" \
     http://localhost:9000/ping
```

O servidor preservará o identificador `transacao-externa-999` e o devolverá intacto nos cabeçalhos e no log do servidor, permitindo rastreabilidade distribuída de ponta a ponta.

---

### Teste 2: Testando o Rate Limiter com Rajada de Chamadas (429 Too Many Requests)

Configuramos o nosso limitador de taxa para admitir no máximo **5 requisições a cada 10 segundos**. Vamos disparar uma rajada de 7 chamadas consecutivas via loop no terminal bash:

```bash
for i in {1..7}; do
  echo "--- Chamada #$i ---"
  curl -s -o /dev/null -w "Status: %{http_code}\n" \
    http://localhost:9000/ping
done
```

**Saída Obtida no Terminal:**

```text
--- Chamada #1 ---
Status: 200
--- Chamada #2 ---
Status: 200
--- Chamada #3 ---
Status: 200
--- Chamada #4 ---
Status: 200
--- Chamada #5 ---
Status: 200
--- Chamada #6 ---
Status: 429
--- Chamada #7 ---
Status: 429
```

Na 6ª chamada, o middleware detectou que a cota do endereço IP `127.0.0.1` foi esgotada na janela ativa, realizando o curto-circuito (*short-circuiting*) e retornando status `429 Too Many Requests`.

Inspecionando o corpo detalhado da 6ª requisição com `curl -i`:

```http
HTTP/1.1 429 Too Many Requests
Retry-After: 10
Content-Type: application/problem+json; charset=utf-8
Content-Length: 228

{"type":"https://api.connectos.com/erros/limite-requisicoes",
 "title":"Muitas Requisicoes",
 "status":429,
 "detail":"Limite de taxa excedido. Aguarde antes de retentar.",
 "instance":"/ping"}
```

---

## 5. ARMADILHAS COMUNS E TROUBLESHOOTING NO FPC/LAZARUS

---

### Armadilha 1: Esquecer de Chamar Next() em Middlewares Não Bloqueantes

**Sintoma:** O cliente dispara uma requisição e a conexão permanece aberta ou a rota manipuladora simplesmente nunca é executada, retornando uma resposta vazia ou incompleta.

**Causa Raiz:** O desenvolvedor escreveu a lógica de um middleware (como autenticação ou auditoria), mas esqueceu de incluir a linha `Next();` no final do fluxo feliz.

**Solução:** Revise o middleware. A menos que a requisição deva ser deliberadamente rejeitada (curto-circuito), a instrução `Next();` deve ser garantidamente invocada.

---

### Armadilha 2: Chamar Next() Duas Vezes na Mesma Requisição

**Sintoma:** Corrupção aleatória de dados, comportamento errático ou violação de acesso (*SIGSEGV*) com logs duplicados para a mesma requisição.

**Causa Raiz:** Estruturas condicionais mal desenhadas onde `Next()` é invocado tanto dentro de um bloco `if` quanto fora dele:

```pascal
{ EQUIVOCO GRAVE: Dupla execucao da cadeia }
if Validar(Req) then
  Next();

Next(); { ERRO: Executa uma segunda vez! }
```

**Solução:** Garanta que cada ramo de execução possua um único caminho que execute `Next()` ou interrompa o procedimento com `Exit`.

---

### Armadilha 3: Gargalo de Contenção em Seções Críticas (Lock Contention)

**Sintoma:** Em testes de estresse com milhares de requisições simultâneas, o servidor em Free Pascal apresenta lentidão generalizada e baixo consumo de CPU, com as threads emperradas em espera.

**Causa Raiz:** Manter operações lentas (como acesso a disco, parsing de JSON ou consultas ao banco de dados) dentro do bloco protegido por `TCriticalSection.Enter` e `Leave`.

**Solução:** Isole na seção crítica **estritamente** a leitura e a escrita das variáveis de memória compartilhadas. Nunca realize operações de rede ou computações pesadas sob o bloqueio da seção crítica.

---

## 6. RESUMO EXECUTIVO E CHECKLIST DE REVISÃO

### Tabela Comparativa de Middlewares

| Middleware | Papel Arquitetural | Momento Crítico | Efeito de Curto-Circuito |
| :--- | :--- | :--- | :--- |
| **Correlation-ID** | Rastreabilidade distribuída | Fase *Before* | Não efetua curto-circuito. |
| **Request Logger** | Telemetria e auditoria de latência | Fase *After* (`finally`) | Não efetua curto-circuito. |
| **Rate Limiter** | Proteção de tráfego e resiliência | Fase *Before* | Emite 429 e cancela chamada da rota. |
| **CORS** | Autorização de origens cruzadas | Fase *Before* | Responde preflight OPTIONS e sai. |

---

### Checklist de Revisão e Auditoria Técnica

Antes de avançar para o Módulo 06, valide a conformidade dos itens:

- [ ] **Ordem de Registro:** Os middlewares globais foram registrados com `THorse.Use(...)` antes de qualquer rota.
- [ ] **Controle do Next():** Os middlewares executam `Next()` exatamente uma vez no caminho de sucesso e o omitem em caso de curto-circuito.
- [ ] **Thread-Safety em Memória:** Qualquer estado mutável compartilhado entre requisições utiliza `TCriticalSection` com proteção estrita em `try..finally`.
- [ ] **Rastreabilidade Universal:** O cabeçalho `X-Correlation-ID` é devolvido em todas as respostas da API e referenciado nos logs do console.
- [ ] **Rate Limiting Funcional:** Teste de rajada comprovou a emissão de status HTTP `429 Too Many Requests` com cabeçalho `Retry-After`.

Com o pipeline de middlewares dominado e blindado contra concorrência, estamos preparados para o **Módulo 06**, onde exploraremos a serialização JSON de alta performance com a biblioteca nativa `fpjson` e a integração com o middleware oficial `horse-jhonson`.
