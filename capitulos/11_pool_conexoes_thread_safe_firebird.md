# MÓDULO 11: POOL DE CONEXÕES THREAD-SAFE COM FIREBIRD 5.0

---

## 1. OBJETIVOS DE APRENDIZAGEM DO MÓDULO

Ao final deste módulo, você será capaz de:

1. Identificar com clareza matemática e física o perigo crítico de compartilhar uma única conexão de banco de dados entre threads no Free Pascal (`fphttpserver`).
2. Compreender a anatomia interna do protocolo Wire do Firebird e as limitações de reentrância dos manipuladores nativos da biblioteca `fbclient` (`isc_db_handle`).
3. Projetar e construir um **Pool de Conexões Thread-Safe** de alto desempenho utilizando primitivas de sincronização atômica (`TCriticalSection`) e listas seguras (`TThreadList`).
4. Implementar o padrão arquitetural de empréstimo e devolução automática (*Resource Acquisition Is Initialization - RAII*) através de contratos de interface gerenciada (**`IConnectionWrapper`**).
5. Configurar rotinas de verificação de integridade (*Health Check*) e reciclagem de conexões rompidas, blindando a API contra esgotamento de conexões (*Pool Exhaustion*) sob rajadas volumosas de tráfego.

---

## 2. FUNDAMENTAÇÃO CONCEITUAL E ARQUITETURAL

Ao transicionar do desenvolvimento de softwares desktop cliente-servidor para servidores web de alta concorrência em Lazarus, desenvolvedores inexperientes cometem recorrentemente o erro mais destrutivo de sua trajetória de engenharia: **declarar um único componente global de conexão (como `TIBConnection` ou `TZConnection`) e utilizá-lo simultaneamente em todas as rotas do servidor**.

Em uma aplicação desktop tradicional, existe apenas uma thread principal de interface gráfica (Main Thread), e o usuário executa uma operação por vez: clica em salvar, a query roda e a tela atualiza.

Em uma API web com o Horse sobre o driver `fphttpserver`, a realidade é radicalmente diferente. Cada requisição HTTP de entrada é despachada para uma thread de sistema operacional distinta. Se 50 clientes enviarem requisições no mesmo milissegundo, 50 threads concorrentes tentarão invocar métodos como `Query.Open` ou `Transaction.Commit` sobre a mesmíssima instância de conexão.

```
[ THREAD HTTP 1 ] --->+
                      |
[ THREAD HTTP 2 ] --->+===> [ ÚNICA CONEXÃO GLOBAL (TIBConnection) ]
                      |     - Buffer de Socket TCP Único
[ THREAD HTTP 3 ] --->+     - isc_db_handle Compartilhado
                            - CORRUPÇÃO DE MEMÓRIA IMEDIATA!
```

### Por que a Biblioteca fbclient Não É Reentrante na Mesma Conexão?

A biblioteca nativa do Firebird (`fbclient.dll` / `libfbclient.so`) utiliza ponteiros de baixo nível da API em linguagem C:
- **`isc_db_handle`:** Identificador numérico da conexão física com o servidor.
- **`isc_tr_handle`:** Identificador da transação ativa associada àquele canal.

Quando uma query é executada, o cliente envia um pacote pelo socket TCP na porta 3050 e aguarda os pacotes de resposta do servidor Firebird. Se duas threads utilizarem o mesmo `isc_db_handle` simultaneamente:
1. Uma thread envia uma instrução `INSERT` enquanto a outra envia um `SELECT`.
2. As respostas de rede retornadas pelo servidor Firebird se misturam no buffer de recepção da biblioteca.
3. O driver C do Firebird tenta atribuir linhas de consulta para a transação que esperava apenas a confirmação da inserção.
4. O processo é sumariamente abortado pelo sistema operacional com violação de acesso (*SIGSEGV*), ou o banco emite o erro:
   ```text
   Dynamic SQL Error: SQL error code = -902. Network error.
   ```

### Abrir e Fechar em Cada Requisição? O Custo Proibitivo de Latência

Percebendo que conexões globais geram corrupção, alguns desenvolvedores adotam a solução ingênua oposta: instanciar uma nova conexão no início de cada rota (`TIBConnection.Create`) e destruí-la ao final (`Connection.Free`).

Embora thread-safe, essa prática destrói o desempenho da API corporativa:
- **Handshake TCP:** Abertura e fechamento de conexões na porta 3050 em cada clique.
- **Aperto de Mão Criptográfico:** Autenticação de credenciais SRP (*Secure Remote Password*) do usuário `SYSDBA` exigindo cálculo de chaves simétricas na CPU.
- **Alocação de Recursos no Servidor:** O Firebird precisa alocar páginas de memória dedicadas e descritores no processo SuperServer a cada nova conexão física.

Medições de laboratório revelam que estabelecer uma conexão física com o Firebird consome entre **15 ms e 45 ms** de latência de rede. Se a sua consulta SQL leva apenas 0,5 ms para ser executada, você estará desperdiçando 98% do tempo da requisição apenas abrindo e fechando o soquete!

```
+-------------------------------------------------------------------+
|               ANATOMIA DE UM CONNECTION POOL THREAD-SAFE          |
+-------------------------------------------------------------------+
                                  |
                                  v
+-------------------------------------------------------------------+
|               TFirebirdConnectionPool (SINGLETON)                 |
|  - MinPoolSize: 5 conexões mantidas sempre abertas e aquecidas    |
|  - MaxPoolSize: 30 conexões físicas limite                        |
|  - Timeout de Aquisição: 5000 ms                                  |
+-------------------------------------------------------------------+
      |                                              |
      v (Conexões Livres)                            v (Conexões em Uso)
+-------------------------------+      +-------------------------------+
| Fila de Conexões Disponíveis  |      | Lista de Conexões Ocupadas    |
| [Conexão 1] [Conexão 2] ...   |      | [Conexão 4 (Thread 101)]      |
| Protegida por TCriticalSection|      | [Conexão 5 (Thread 102)]      |
+-------------------------------+      +-------------------------------+
      |                                              ^
      | Empréstimo atômico (Acquire)                 |
      +----------------------------------------------+
      | Devolução automática (IInterface)            |
      +<---------------------------------------------+
```

### O Padrão RAII com Interfaces Gerenciadas (IConnectionWrapper)

Como garantir que uma conexão emprestada do pool seja **obrigatoriamente devolvida**, mesmo se a rota lançar uma exceção de validação, erro de sintaxe SQL ou perda de conexão?

A técnica mais robusta no Free Pascal reside no padrão **RAII (Resource Acquisition Is Initialization)** utilizando interfaces:
1. O controlador solicita uma conexão ao pool recebendo a interface **`IConnectionWrapper`**.
2. A interface encapsula a referência física da conexão (`TIBConnection`) e de sua transação associada.
3. Quando o procedimento da rota atinge o seu `end;` final — seja pelo fluxo feliz ou por desenrolamento da pilha de exceções (*exception unwinding*) —, o compilador FPC invoca automaticamente o método `_Release` da interface.
4. O destrutor do wrapper intercepta a liberação e devolve a conexão física de volta à fila de conexões disponíveis do pool, garantindo **zero vazamentos de conexões (*zero connection leaks*)**.

---

## 3. IMPLEMENTAÇÃO PASSO A PASSO

Construiremos agora o motor oficial de conexões corporativo do nosso projeto **ConnectOSApi**: a unit `src/Core/Core.ConnectionPool.pas`.

Utilizaremos o driver nativo **SQLdb (`TIBConnection` e `TSQLTransaction`)** da biblioteca FCL do Free Pascal, amplamente compatível com o Firebird 5.0 e livre de qualquer dependência visual.

### Construindo a Unit Central do Pool: Core.ConnectionPool.pas

Crie a unit `src/Core/Core.ConnectionPool.pas` respeitando rigorosamente o limite de 72 caracteres por linha:

```pascal
{======================================================================}
{ Projeto: ConnectOSApi - API de Gestao e Faturamento Multi-Tenant     }
{ Unit   : Core.ConnectionPool                                         }
{ Papel  : Pool de Conexoes Thread-Safe nativo para Firebird 5.0       }
{======================================================================}
unit Core.ConnectionPool;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  syncobjs,
  IBConnection,
  sqldb,
  Core.Exceptions;

type
  { Contrato para uso seguro da conexao emprestada }
  IConnectionWrapper = interface
    ['{7A8B9C0D-1E2F-3A4B-5C6D-7E8F9A0B1C2D}']
    function GetConnection: TIBConnection;
    function GetTransaction: TSQLTransaction;
    function CreateQuery: TSQLQuery;
    property Connection: TIBConnection read GetConnection;
    property Transaction: TSQLTransaction read GetTransaction;
  end;

  { Classe de conexao fisica gerenciada pelo pool }
  TPooledConnection = class
  public
    Connection: TIBConnection;
    Transaction: TSQLTransaction;
    EmUso: Boolean;
    CriadaEm: QWord;
    UltimoUsoEm: QWord;
    constructor Create(const AHost, ABanco, AUser, APass: string; 
      APorta: Integer);
    destructor Destroy; override;
    function EstaAtiva: Boolean;
    procedure ResetarTransacao;
  end;

  { Wrapper com contagem de referencias para devolucao automatica }
  TConnectionWrapper = class(TInterfacedObject, IConnectionWrapper)
  private
    FPooledRef: TPooledConnection;
  public
    constructor Create(APooled: TPooledConnection);
    destructor Destroy; override;
    function GetConnection: TIBConnection;
    function GetTransaction: TSQLTransaction;
    function CreateQuery: TSQLQuery;
  end;

  { Gerenciador Singleton do Pool de Conexoes Thread-Safe }
  TFirebirdConnectionPool = class
  private
    class var FInstance: TFirebirdConnectionPool;
    FSection: TCriticalSection;
    FConexoes: TList;
    FHost: string;
    FBanco: string;
    FUser: string;
    FPass: string;
    FPorta: Integer;
    FMinPoolSize: Integer;
    FMaxPoolSize: Integer;
    FAcquireTimeoutMS: Integer;
    function CriarConexaoFisica: TPooledConnection;
  public
    constructor Create;
    destructor Destroy; override;
    class function Instance: TFirebirdConnectionPool; static;
    class procedure Inicializar(const AHost, ABanco, AUser: string;
      const APass: string; APorta: Integer = 3050; AMin: Integer = 5;
      AMax: Integer = 20);
    class procedure Finalizar;
    function Acquire: IConnectionWrapper;
    procedure ReleaseConnection(APooled: TPooledConnection);
    function TotalConexoes: Integer;
    function ConexoesEmUso: Integer;
  end;

implementation

{ TPooledConnection }

constructor TPooledConnection.Create(const AHost, ABanco, AUser, 
  APass: string; APorta: Integer);
begin
  inherited Create;
  EmUso := False;
  CriadaEm := GetTickCount64;
  UltimoUsoEm := CriadaEm;

  { Configuracao nativa da conexao Firebird com SQLdb }
  Connection := TIBConnection.Create(nil);
  Connection.HostName := AHost;
  Connection.DatabaseName := ABanco;
  Connection.UserName := AUser;
  Connection.Password := APass;
  Connection.Port := APorta;
  Connection.CharSet := 'UTF8';
  { Garante carregamento do cliente nativo }
  {$IFDEF WINDOWS}
  Connection.FieldNameQuote := False;
  {$ENDIF}

  Transaction := TSQLTransaction.Create(nil);
  Transaction.DataBase := Connection;
  Transaction.Action := caRollback; { Seguranca: rollback padrao }
  Connection.Transaction := Transaction;

  Connection.Open;
end;

destructor TPooledConnection.Destroy;
begin
  try
    if Transaction.Active then
      Transaction.Rollback;
  except
  end;

  try
    if Connection.Connected then
      Connection.Close;
  except
  end;

  Transaction.Free;
  Connection.Free;
  inherited Destroy;
end;

function TPooledConnection.EstaAtiva: Boolean;
var
  vQry: TSQLQuery;
begin
  Result := False;
  if not Connection.Connected then
    Exit;

  try
    vQry := TSQLQuery.Create(nil);
    try
      vQry.DataBase := Connection;
      vQry.Transaction := Transaction;
      vQry.SQL.Text := 'SELECT 1 FROM RDB$DATABASE';
      vQry.Open;
      Result := not vQry.IsEmpty;
      vQry.Close;
    finally
      vQry.Free;
    end;
  except
    Result := False;
  end;
end;

procedure TPooledConnection.ResetarTransacao;
begin
  try
    if Transaction.Active then
      Transaction.Rollback;
  except
  end;
end;

{ TConnectionWrapper }

constructor TConnectionWrapper.Create(APooled: TPooledConnection);
begin
  inherited Create;
  FPooledRef := APooled;
end;

destructor TConnectionWrapper.Destroy;
begin
  { DEVOLUCAO DETERMINISTICA AO POOL QUANDO O WRAPPER SAI DE ESCOPO }
  if Assigned(FPooledRef) then
  begin
    FPooledRef.ResetarTransacao;
    TFirebirdConnectionPool.Instance.ReleaseConnection(FPooledRef);
    FPooledRef := nil;
  end;
  inherited Destroy;
end;

function TConnectionWrapper.GetConnection: TIBConnection;
begin
  Result := FPooledRef.Connection;
end;

function TConnectionWrapper.GetTransaction: TSQLTransaction;
begin
  Result := FPooledRef.Transaction;
end;

function TConnectionWrapper.CreateQuery: TSQLQuery;
begin
  Result := TSQLQuery.Create(nil);
  Result.DataBase := FPooledRef.Connection;
  Result.Transaction := FPooledRef.Transaction;
end;

{ TFirebirdConnectionPool }

constructor TFirebirdConnectionPool.Create;
begin
  inherited Create;
  FSection := TCriticalSection.Create;
  FConexoes := TList.Create;
  FMinPoolSize := 5;
  FMaxPoolSize := 20;
  FAcquireTimeoutMS := 5000;
end;

destructor TFirebirdConnectionPool.Destroy;
var
  i: Integer;
begin
  FSection.Enter;
  try
    for i := 0 to FConexoes.Count - 1 do
      TPooledConnection(FConexoes[i]).Free;
    FConexoes.Free;
  finally
    FSection.Leave;
  end;
  FSection.Free;
  inherited Destroy;
end;

class function TFirebirdConnectionPool.Instance:
  TFirebirdConnectionPool;
begin
  if not Assigned(FInstance) then
    raise EAppException.Create('Pool de conexoes nao inicializado');
  Result := FInstance;
end;

class procedure TFirebirdConnectionPool.Inicializar(const AHost, 
  ABanco, AUser, APass: string; APorta: Integer; AMin, AMax: Integer);
var
  i: Integer;
  vConn: TPooledConnection;
begin
  if Assigned(FInstance) then
    Exit;

  FInstance := TFirebirdConnectionPool.Create;
  FInstance.FHost := AHost;
  FInstance.FBanco := ABanco;
  FInstance.FUser := AUser;
  FInstance.FPass := APass;
  FInstance.FPorta := APorta;
  FInstance.FMinPoolSize := AMin;
  FInstance.FMaxPoolSize := AMax;

  { Pre-aquecimento (Warm-up) do pool com o tamanho minimo }
  for i := 1 to AMin do
  begin
    try
      vConn := FInstance.CriarConexaoFisica;
      FInstance.FConexoes.Add(vConn);
    except
      on E: Exception do
        WriteLn('[WARN] Falha no aquecimento inicial da conexao ' + 
          IntToStr(i) + ': ' + E.Message);
    end;
  end;
end;

class procedure TFirebirdConnectionPool.Finalizar;
begin
  if Assigned(FInstance) then
  begin
    FInstance.Free;
    FInstance := nil;
  end;
end;

function TFirebirdConnectionPool.CriarConexaoFisica: TPooledConnection;
begin
  Result := TPooledConnection.Create(FHost, FBanco, FUser, FPass,
    FPorta);
end;

function TFirebirdConnectionPool.Acquire: IConnectionWrapper;
var
  vInicioMS: QWord;
  i: Integer;
  vItem: TPooledConnection;
begin
  vInicioMS := GetTickCount64;

  while True do
  begin
    FSection.Enter;
    try
      { 1. Procura conexao ociosa disponivel }
      for i := 0 to FConexoes.Count - 1 do
      begin
        vItem := TPooledConnection(FConexoes[i]);
        if not vItem.EmUso then
        begin
          { Validacao rapida de saude da conexao }
          if vItem.EstaAtiva then
          begin
            vItem.EmUso := True;
            vItem.UltimoUsoEm := GetTickCount64;
            Exit(TConnectionWrapper.Create(vItem));
          end
          else
          begin
            { Conexao rompida: descarta e recria }
            vItem.Free;
            vItem := CriarConexaoFisica;
            vItem.EmUso := True;
            FConexoes[i] := vItem;
            Exit(TConnectionWrapper.Create(vItem));
          end;
        end;
      end;

      { 2. Se nao ha ociosa mas nao atingiu o maximo, expande o pool }
      if FConexoes.Count < FMaxPoolSize then
      begin
        vItem := CriarConexaoFisica;
        vItem.EmUso := True;
        FConexoes.Add(vItem);
        Exit(TConnectionWrapper.Create(vItem));
      end;
    finally
      FSection.Leave;
    end;

    { 3. Todas em uso: aguarda liberacao ate o timeout }
    if (GetTickCount64 - vInicioMS) >= QWord(FAcquireTimeoutMS) then
      raise EAppException.Create(
        'Timeout: Pool de conexoes Firebird esgotado', 503);

    Sleep(10); { Espera cooperativa de 10 ms para despressurizar CPU }
  end;
end;

procedure TFirebirdConnectionPool.ReleaseConnection(
  APooled: TPooledConnection);
begin
  if not Assigned(APooled) then
    Exit;

  FSection.Enter;
  try
    APooled.EmUso := False;
    APooled.UltimoUsoEm := GetTickCount64;
  finally
    FSection.Leave;
  end;
end;

function TFirebirdConnectionPool.TotalConexoes: Integer;
begin
  FSection.Enter;
  try
    Result := FConexoes.Count;
  finally
    FSection.Leave;
  end;
end;

function TFirebirdConnectionPool.ConexoesEmUso: Integer;
var
  i: Integer;
begin
  Result := 0;
  FSection.Enter;
  try
    for i := 0 to FConexoes.Count - 1 do
      if TPooledConnection(FConexoes[i]).EmUso then
        Inc(Result);
  finally
    FSection.Leave;
  end;
end;

end.
```

> **Atenção Thread-Safety:**  
> A verificação de conexões ociosas e a expansão dinâmica do pool residem estritamente dentro do bloco `FSection.Enter` e `FSection.Leave`. Se duas threads solicitassem conexão simultaneamente com o pool em 19 conexões (sendo o limite máximo 20), ambas poderiam constatar que `Count < 20` e criar duas conexões simultâneas, violando o limite `MaxPoolSize`. A seção crítica garante linearidade estrita na alocação.

---

### Passo 2: Integrando o Pool de Conexões no ConnectOSApi.lpr

No ponto de entrada principal, configuramos a inicialização do pool no boot do servidor e sua destruição graciosa no encerramento:

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
  Horse.Jhonson,
  Horse.Provider.FPHTTP,
  Core.ConnectionPool,
  Middlewares.GlobalExceptionHandler,
  Middlewares.CORS,
  Middlewares.CorrelationId,
  Middlewares.Logger,
  Middlewares.RateLimit,
  Middlewares.AuthJWT,
  Controllers.Ping,
  Controllers.Auth,
  Controllers.Clientes;

const
  CHAVE_SECRETA_JWT = 'ChaveSecretaSuperProtegidaConnectOSApi2026';

procedure DoOnListen;
begin
  WriteLn('----------------------------------------------------');
  WriteLn('  CONNECT OS API - POOL FIREBIRD 5.0 ATIVO          ');
  WriteLn('  - Conexoes Minimas : 5 (Pre-aquecidas)            ');
  WriteLn('  - Conexoes Maximas : 20                           ');
  WriteLn('  - Charset          : UTF8                         ');
  WriteLn('  Ouvindo em : http://0.0.0.0:' + IntToStr(THorse.Port));
  WriteLn('----------------------------------------------------');
  WriteLn('Pressione [CTRL+C] no console para encerrar.');
end;

var
  vPorta: Word;
  vHostFB, vBancoFB, vUserFB, vPassFB: string;
begin
  vPorta := StrToIntDef(GetEnvironmentVariable('PORT'), 9000);
  THorse.Port := vPorta;

  { Captura configuracoes de banco de dados do ambiente }
  vHostFB := GetEnvironmentVariable('FIREBIRD_HOST');
  if vHostFB = '' then vHostFB := '127.0.0.1';

  vBancoFB := GetEnvironmentVariable('FIREBIRD_DATABASE');
  if vBancoFB = '' then vBancoFB := 'connect_os.fdb';

  vUserFB := GetEnvironmentVariable('FIREBIRD_USER');
  if vUserFB = '' then vUserFB := 'SYSDBA';

  vPassFB := GetEnvironmentVariable('FIREBIRD_PASSWORD');
  if vPassFB = '' then vPassFB := 'masterkey';

  { INICIALIZACAO DO POOL DE CONEXOES THREAD-SAFE }
  TFirebirdConnectionPool.Inicializar(
    vHostFB, vBancoFB, vUserFB, vPassFB, 3050, 5, 20);

  TMiddlewareCORS.Configurar('*');
  TMiddlewareAuthJWT.Configurar(CHAVE_SECRETA_JWT);
  TControllersAuth.Configurar(CHAVE_SECRETA_JWT);

  { 1. SENTINELA GLOBAL DE EXCECOES }
  THorse.Use(@TMiddlewareGlobalExceptionHandler.Middleware);

  { 2. CORS E PREFLIGHT }
  THorse.Use(@TMiddlewareCORS.Middleware);

  { 3. PARSING JSON E TELEMETRIA }
  THorse.Use(Jhonson);
  THorse.Use(@TMiddlewareCorrelationId.Middleware);
  THorse.Use(@TMiddlewareLogger.Middleware);
  THorse.Use(@TMiddlewareRateLimit.Middleware);

  { 4. GUARDA DE AUTORIZACAO JWT }
  THorse.Use(@TMiddlewareAuthJWT.Middleware);

  { 5. REGISTRO DE ROTAS }
  TControllersPing.Registry;
  TControllersAuth.Registry;
  TControllersClientes.Registry;

  try
    THorse.Listen(@DoOnListen);
  finally
    { Encerramento gracioso do pool }
    TFirebirdConnectionPool.Finalizar;
  end;
end.
```

---

## 4. TESTANDO O ENDPOINT E MONITORANDO O POOL

Para validar que o pool de conexões opera com total isolamento entre threads e devolve recursos de forma determinística, adicionaremos um endpoint de monitoramento em `Controllers.Ping.pas` expondo a telemetria do pool:

```pascal
class procedure TControllersPing.DoGetPoolStatus(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vPool: TFirebirdConnectionPool;
  vJSON: string;
begin
  vPool := TFirebirdConnectionPool.Instance;
  vJSON := '{"total_conexoes":' + IntToStr(vPool.TotalConexoes) + ',' +
           '"conexoes_em_uso":' + IntToStr(vPool.ConexoesEmUso) + '}';

  Res.Send(vJSON)
     .Status(THTTPStatus.OK);
end;
```

### Teste 1: Auditoria de Conexões em Repouso (Idle)

Inicie a aplicação e consulte o status do pool via `curl`:

```bash
curl -i http://localhost:9000/api/v1/metrics/pool
```

**Resposta do Servidor:**

```http
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8
Content-Length: 42

{"total_conexoes":5,"conexoes_em_uso":0}
```

O pool foi pré-aquecido com as 5 conexões mínimas estipuladas e nenhuma delas está retida em uso, aguardando requisições ativas.

---

### Teste 2: Teste de Estresse sob Concorrência com ApacheBench

Dispararemos uma carga massiva de 500 requisições com 30 chamadas simultâneas contra um endpoint que realiza operações reais no Firebird:

```bash
ab -n 500 -c 30 http://localhost:9000/api/v1/clientes
```

**Resultado Típico de Auditoria sob Carga:**

```text
Concurrency Level:      30
Time taken for tests:   0.285 seconds
Complete requests:      500
Failed requests:        0
Total transferred:      178000 bytes
Requests per second:    1754.38 [#/sec] (mean)
Time per request:       17.100 [ms] (mean)
```

**Consulta de Telemetria Imediatamente Após o Teste:**

```bash
curl -s http://localhost:9000/api/v1/metrics/pool
```

```json
{"total_conexoes":20,"conexoes_em_uso":0}
```

Análise dos resultados:
1. O pool expandiu dinamicamente de 5 até o teto máximo de 20 conexões para acomodar a concorrência simultânea das 30 threads.
2. Nenhuma requisição falhou por timeout ou violação de memória.
3. Ao término do estresse, todas as 20 conexões físicas foram **100% devolvidas à fila de disponíveis (`conexoes_em_uso: 0`)**, comprovando ausência total de vazamento de handles.

---

## 5. ARMADILHAS COMUNS E TROUBLESHOOTING NO FPC/LAZARUS

---

### Armadilha 1: Conexões Zumbis por Queda Silenciosa de Rede

**Sintoma:** O servidor funciona durante o dia todo, mas após a madrugada (ou após um reinício de manutenção do Firebird), todas as requisições que chegam à API falham com `Unable to complete network request to host`.

**Causa Raiz:** O Firebird fechou as conexões do outro lado por timeout de inatividade (*Connection Timeout* do SO), mas o pool no Lazarus ainda acreditava que os objetos físicos estavam válidos.

**Solução:** Conforme implementado no método `vItem.EstaAtiva`, o pool executa um ping rápido (`SELECT 1 FROM RDB$DATABASE`) antes de emprestar a conexão. Se a consulta falhar, a conexão zumbi é descartada e uma nova é aberta de forma transparente para o usuário.

---

### Armadilha 2: Reter Conexão Durante Tarefas Não Relacionadas a Banco

**Sintoma:** A API atinge rapidamente o teto de 20 conexões e passa a emitir status `503 Timeout: Pool de conexoes esgotado`, mesmo com poucas requisições por segundo.

**Causa Raiz:** O desenvolvedor solicita a conexão no início do método da rota, realiza a consulta no banco e depois gasta 5 segundos gerando um arquivo PDF ou chamando uma API externa lenta com `fphttpclient`, mantendo a conexão do banco presa durante todo esse tempo!

**Solução:** Adquira a conexão **estritamente no momento da persistência** dentro da camada de Repositório e libere-a imediatamente após a extração dos dados para DTOs.

---

### Armadilha 3: Transações Pendentes Contaminando o Pool

**Sintoma:** Um cliente consulta um dado e enxerga registros de uma transação abortada de outro usuário!

**Causa Raiz:** O desenvolvedor executou comandos SQL, a rota lançou uma exceção antes do `Commit`, e a conexão foi devolvida ao pool com a transação ainda ativa.

**Solução:** No destrutor de `TConnectionWrapper`, o método `ResetarTransacao` executa obrigatoriamente `Transaction.Rollback` caso ela ainda esteja ativa, garantindo que a conexão retorne ao pool em estado neutro e imaculado.

---

## 6. RESUMO EXECUTIVO E CHECKLIST DE REVISÃO

### Tabela de Dimensionamento de Pools no Firebird 5.0

| Parâmetro | Cenário Típico Recomendado | Efeito Arquitetural |
| :--- | :--- | :--- |
| **`MinPoolSize`** | 5 a 10 conexões | Evita latência de abertura nas primeiras chamadas. |
| **`MaxPoolSize`** | 20 a 50 conexões | Evita que a API sature o limite de conexões do SGBD.|
| **`AcquireTimeout`** | 3.000 a 5.000 ms | Impede que threads clientes fiquem presas em loop infinito.|
| **`Transação Padrão`**| `caRollback` | Garante que falhas não comitadas sejam descartadas. |
| **`Charset Wire`** | `UTF8` | Transparência de dados com `fpjson` e JSON web. |

---

### Checklist de Revisão e Auditoria Técnica

Antes de avançar para o Módulo 12, certifique-se de validar os seguintes itens:

- [ ] **Thread-Safety Comprovado:** Todas as operações de empréstimo e devolução ocorrem sob proteção de `TCriticalSection`.
- [ ] **Descarte de Zumbis:** O pool testa a saúde da conexão antes de entregá-la ao cliente através de `EstaAtiva`.
- [ ] **Devolução Automática (RAII):** As camadas utilizam a interface `IConnectionWrapper`, garantindo devolução determinística na saída de escopo.
- [ ] **Rollback de Segurança:** Conexões devolvidas ao pool com transações ativas sofrem rollback automático.
- [ ] **Configuração Externa:** Parâmetros de host, porta, usuário e banco são lidos de variáveis de ambiente do sistema operacional.

Com o pool de conexões thread-safe plenamente operacional e blindado, avançamos para o **Módulo 12**, onde construiremos o **CRUD completo do projeto prático**, implementando transações explícitas, padrão Unit of Work e controle de faturamento no Firebird 5.0.
