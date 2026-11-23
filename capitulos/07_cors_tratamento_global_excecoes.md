# MÓDULO 07: CORS E TRATAMENTO GLOBAL DE EXCEÇÕES

---

## 1. OBJETIVOS DE APRENDIZAGEM DO MÓDULO

Ao final deste módulo, você será capaz de:

1. Compreender a mecânica do mecanismo **CORS (Cross-Origin Resource Sharing)** e a Política de Mesma Origem (*Same-Origin Policy* - SOP) imposta pelos navegadores modernos.
2. Identificar e atender com precisão as requisições de pré-voo (**Preflight Requests**) enviadas via método HTTP `OPTIONS`, configurando cabeçalhos canônicos de controle de acesso.
3. Projetar uma hierarquia tipada de exceções de domínio em Object Pascal (`EAppException`, `EBusinessException`, `ENotFoundException`, `EConflictException`), desacoplando as regras de negócio das camadas de transporte HTTP.
4. Construir e registrar um interceptador global de exceções (**Global Exception Handler**) posicionado como sentinela de entrada no pipeline do Horse.
5. Blindar o servidor contra vazamento de informações sensíveis em produção, convertendo exceções catastróficas não tratadas em documentos RFC 7807 genéricos com registro de auditoria (*Correlation-ID*).

---

## 2. FUNDAMENTAÇÃO CONCEITUAL E ARQUITETURAL

No modelo de computação clássico baseado em arquiteturas monolíticas de renderização no servidor (SSR), o navegador web requisitava páginas HTML e recursos estáticos provenientes exatamente do mesmo domínio, protocolo e porta da aplicação.

Com a consolidação das **Single Page Applications (SPAs)** desenvolvidas em ecossistemas modernos (React, Vue, Angular) e a proliferação de aplicativos móveis híbridos (Flutter, React Native), o frontend frequentemente reside em uma origem distinta (ex: `https://app.connectos.com` ou `http://localhost:3000`) do servidor de API backend (ex: `https://api.connectos.com:9000`).

Diante desse cenário, os navegadores web acionam um rigoroso mecanismo de segurança embutido no padrão W3C: a **Política de Mesma Origem (SOP)**. Para que um script executado no navegador possa ler dados retornados por uma API residente em outra origem, o servidor backend precisa autorizar explicitamente a comunicação através do protocolo **CORS (Cross-Origin Resource Sharing)**.

```
+-------------------------------------------------------------------+
|              CICLO DE VIDA DA REQUISIÇÃO COM PREFLIGHT            |
+-------------------------------------------------------------------+
  CLIENTE (Browser / SPA)                          SERVIDOR HORSE
            |                                             |
            | 1. [OPTIONS Preflight]                      |
            |    Origin: https://app.conectos.com         |
            |    Access-Control-Request-Method: POST      |
            |    Access-Control-Request-Headers: X-Tenant |
            |-------------------------------------------->|
            |                                             |
            | 2. [Resposta 204 No Content]                |
            |    Access-Control-Allow-Origin: ...         |
            |    Access-Control-Allow-Methods: ...        |
            |    Access-Control-Allow-Headers: ...        |
            |<--------------------------------------------|
            |                                             |
            | 3. [Requisição Real: POST /api/v1/clientes] |
            |    X-Tenant-ID: 1                           |
            |    Body: {"nome_razao":"Acme"}              |
            |-------------------------------------------->|
            |                                             |
            | 4. [Resposta 201 Created]                   |
            |<--------------------------------------------|
```

### Anatomia da Requisição de Pré-Voo (Preflight Request)

Antes de disparar chamadas com métodos potencialmente mutáveis (`POST`, `PUT`, `DELETE`, `PATCH`) ou contendo cabeçalhos customizados (como `Authorization` e `X-Tenant-ID`), o navegador emite uma requisição preliminar e transparente ao usuário: a chamada **Preflight** via método HTTP **`OPTIONS`**.

Se o servidor backend não souber responder à chamada `OPTIONS` com o conjunto exato de cabeçalhos CORS, o navegador bloqueia a requisição imediatamente no lado do cliente com o erro clássico:

```text
Access to fetch at 'https://api.connectos.com' from origin 
'https://app.connectos.com' has been blocked by CORS policy.
```

Para pacificar o navegador, o servidor deve emitir os seguintes cabeçalhos de controle:
- **`Access-Control-Allow-Origin`:** Especifica quais domínios têm permissão para ler a resposta. Em ambientes de produção bancária ou SaaS corporativo, **nunca** utilize o curinga `*` com credenciais; defina a lista de origens autorizadas.
- **`Access-Control-Allow-Methods`:** Lista dos verbos HTTP permitidos (`GET, POST, PUT, PATCH, DELETE, OPTIONS`).
- **`Access-Control-Allow-Headers`:** Lista dos cabeçalhos customizados que o cliente pode transmitir (`Content-Type, Authorization, X-Tenant-ID, X-Correlation-ID`).
- **`Access-Control-Max-Age`:** Tempo em segundos (ex: 86.400 segundos / 24 horas) durante o qual o navegador pode memorizar a autorização, dispensando preflights repetidos.

> **Nota de Arquitetura:**  
> Ao utilizar tokens em cookies ou cabeçalhos autenticados (`Authorization: Bearer`), a especificação W3C proíbe estritamente o uso de `Access-Control-Allow-Origin: *` em conjunto com `Access-Control-Allow-Credentials: true`. A origem deve ser estritamente espelhada ou validada contra uma lista branca (*whitelist*).

---

### A Hierarquia de Exceções de Domínio e o Princípio Fail-Safe

O segundo pilar de robustez de uma API reside no gerenciamento de falhas. Em sistemas mal projetados, controladores acumulam dezenas de blocos `try..except` manuais para testar cada possível erro de banco de dados, conversão de data ou validação de chave estrangeira.

Na Arquitetura Limpa, aplicamos o desacoplamento estrito de erros:
1. **Camadas Internas (Services e Repositories):** Não conhecem HTTP. Elas nunca referenciam `THorseResponse` nem decidem códigos de status. Se uma regra de negócio for violada, o serviço simplesmente lança uma **Exceção de Domínio Tipada** (ex: `raise EBusinessException.Create('Saldo insuficiente');`).
2. **Camada de Borda (Global Exception Handler):** Um único middleware sentinela, posicionado no topo da cadeia do Horse, intercepta qualquer exceção lançada em qualquer camada da aplicação e a traduz automaticamente para o código de status HTTP correspondente e para a estrutura RFC 7807 (Problem Details).

```
[ EXCEÇÃO DE NEGÓCIO LANÇADA NA SERVICE ]
raise ENotFoundException.Create('Cliente não cadastrado');
                      |
                      v (Propaga-se pela pilha)
                      |
[ INTERCEPTADOR GLOBAL DE EXCEÇÕES (MIDDLEWARE) ]
                      |
                      +---> É ENotFoundException?   --> Emite HTTP 404
                      +---> É EBusinessException?   --> Emite HTTP 422
                      +---> É EConflictException?   --> Emite HTTP 409
                      +---> É Exceção Inesperada?   --> Loga e Emite 500
```

---

## 3. IMPLEMENTAÇÃO PASSO A PASSO

Construiremos agora a infraestrutura de segurança e tratamento de exceções do nosso projeto **ConnectOSApi**:
1. `Core.Exceptions.pas`: Hierarquia orientada a objetos de exceções de domínio.
2. `Middlewares.CORS.pas`: Middleware nativo de controle de origens cruzadas e preflight OPTIONS.
3. `Middlewares.GlobalExceptionHandler.pas`: Interceptador sentinela com mapeamento automático para a RFC 7807.

### Passo 1: Construindo a Hierarquia de Exceções: Core.Exceptions.pas

Crie a unit `src/Core/Core.Exceptions.pas` definindo as classes de erro de domínio com seus respectivos códigos de status HTTP embutidos:

```pascal
{======================================================================}
{ Projeto: ConnectOSApi - API de Gestao e Faturamento Multi-Tenant     }
{ Unit   : Core.Exceptions                                             }
{ Papel  : Hierarquia tipada de excecoes de dominio da aplicacao       }
{======================================================================}
unit Core.Exceptions;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  { Excecao base de todas as falhas de aplicacao controladas }
  EAppException = class(Exception)
  private
    FStatusCode: Integer;
    FErrorCode: string;
  public
    constructor Create(const AMsg: string; AStatus: Integer = 400; 
      const AErrCode: string = 'ERRO_APLICACAO');
    property StatusCode: Integer read FStatusCode;
    property ErrorCode: string read FErrorCode;
  end;

  { 422 Unprocessable Entity - Regra de negocio violada }
  EBusinessException = class(EAppException)
  public
    constructor Create(const AMsg: string; 
      const AErrCode: string = 'REGRA_NEGOCIO_VIOLADA');
  end;

  { 404 Not Found - Entidade solicitada inexistente }
  ENotFoundException = class(EAppException)
  public
    constructor Create(const AMsg: string; 
      const AErrCode: string = 'RECURSO_NAO_ENCONTRADO');
  end;

  { 409 Conflict - Conflito de estado ou unicidade violada }
  EConflictException = class(EAppException)
  public
    constructor Create(const AMsg: string; 
      const AErrCode: string = 'CONFLITO_ESTADO');
  end;

  { 401 Unauthorized - Autenticacao ausente ou token invalido }
  EUnauthorizedException = class(EAppException)
  public
    constructor Create(const AMsg: string = 'Credenciais invalidas'; 
      const AErrCode: string = 'NAO_AUTORIZADO');
  end;

  { 403 Forbidden - Usuario autenticado sem permissao de acesso }
  EForbiddenException = class(EAppException)
  public
    constructor Create(const AMsg: string = 'Acesso negado ao recurso'; 
      const AErrCode: string = 'ACESSO_PROIBIDO');
  end;

implementation

{ EAppException }

constructor EAppException.Create(const AMsg: string; AStatus: Integer; 
  const AErrCode: string);
begin
  inherited Create(AMsg);
  FStatusCode := AStatus;
  FErrorCode := AErrCode;
end;

{ EBusinessException }

constructor EBusinessException.Create(const AMsg: string; 
  const AErrCode: string);
begin
  inherited Create(AMsg, 422, AErrCode);
end;

{ ENotFoundException }

constructor ENotFoundException.Create(const AMsg: string; 
  const AErrCode: string);
begin
  inherited Create(AMsg, 404, AErrCode);
end;

{ EConflictException }

constructor EConflictException.Create(const AMsg: string; 
  const AErrCode: string);
begin
  inherited Create(AMsg, 409, AErrCode);
end;

{ EUnauthorizedException }

constructor EUnauthorizedException.Create(const AMsg: string; 
  const AErrCode: string);
begin
  inherited Create(AMsg, 401, AErrCode);
end;

{ EForbiddenException }

constructor EForbiddenException.Create(const AMsg: string; 
  const AErrCode: string);
begin
  inherited Create(AMsg, 403, AErrCode);
end;

end.
```

---

### Passo 2: Construindo o Middleware Customizado de CORS: Middlewares.CORS.pas

Crie a unit `src/Core/Middlewares.CORS.pas`. Ela gerencia as requisições Preflight `OPTIONS` e injeta os cabeçalhos de segurança em conformidade com o limite de 72 caracteres por linha:

```pascal
{======================================================================}
{ Projeto: ConnectOSApi - API de Gestao e Faturamento Multi-Tenant     }
{ Unit   : Middlewares.CORS                                            }
{ Papel  : Gerenciamento robusto de Cross-Origin Resource Sharing      }
{======================================================================}
unit Middlewares.CORS;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  Horse;

type
  TMiddlewareCORS = class
  private
    class var FOrigensPermitidas: string;
  public
    class procedure Configurar(const AOrigens: string);
    class procedure Middleware(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
  end;

implementation

{ TMiddlewareCORS }

class procedure TMiddlewareCORS.Configurar(const AOrigens: string);
begin
  FOrigensPermitidas := AOrigens;
end;

class procedure TMiddlewareCORS.Middleware(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vOrigin: string;
begin
  vOrigin := Req.Headers.Field('Origin').AsString;

  { Emissao dos cabecalhos universais de CORS }
  if FOrigensPermitidas = '*' then
    Res.RawWebResponse.SetCustomHeader(
      'Access-Control-Allow-Origin', '*')
  else if vOrigin <> '' then
    Res.RawWebResponse.SetCustomHeader('Access-Control-Allow-Origin', 
      vOrigin);

  Res.RawWebResponse.SetCustomHeader('Access-Control-Allow-Methods', 
    'GET, POST, PUT, PATCH, DELETE, OPTIONS');
  Res.RawWebResponse.SetCustomHeader('Access-Control-Allow-Headers', 
    'Content-Type, Authorization, X-Tenant-ID, X-Correlation-ID');
  Res.RawWebResponse.SetCustomHeader(
    'Access-Control-Allow-Credentials', 'true');
  Res.RawWebResponse.SetCustomHeader('Access-Control-Max-Age', '86400');

  { CURTO-CIRCUITO DE PREFLIGHT: Se for OPTIONS, finaliza com 204 }
  if SameText(Req.RawWebRequest.Method, 'OPTIONS') then
  begin
    Res.Status(THTTPStatus.NoContent);
    Exit; { NAO INVOCA NEXT() }
  end;

  Next();
end;

end.
```

---

### Passo 3: O Interceptador Global de Exceções: Middlewares.GlobalExceptionHandler.pas

A unit `src/Core/Middlewares.GlobalExceptionHandler.pas` encapsula o pipeline inteiro em um bloco protetor `try..except`. Ela distingue exceções de domínio de falhas graves de sistema, protegendo o servidor contra vazamento de stack traces e dados sensíveis:

```pascal
{======================================================================}
{ Projeto: ConnectOSApi - API de Gestao e Faturamento Multi-Tenant     }
{ Unit   : Middlewares.GlobalExceptionHandler                          }
{ Papel  : Interceptador global de falhas e formatador RFC 7807       }
{======================================================================}
unit Middlewares.GlobalExceptionHandler;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  Horse,
  Core.Exceptions,
  Core.ProblemDetails;

type
  TMiddlewareGlobalExceptionHandler = class
  public
    class procedure Middleware(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
  end;

implementation

{ TMiddlewareGlobalExceptionHandler }

class procedure TMiddlewareGlobalExceptionHandler.Middleware(
  Req: THorseRequest; Res: THorseResponse; Next: TNextProc);
var
  vCorrelationId: string;
begin
  try
    { Executa o restante de toda a aplicacao de forma protegida }
    Next();
  except
    on E: EAppException do
    begin
      { FALHA CONTROLADA: Excecao conhecida de Dominio da Aplicacao }
      vCorrelationId := 
        Res.RawWebResponse.GetCustomHeader('X-Correlation-ID');

      TProblemDetails.CreateNew
        .SetType('https://api.connectos.com/erros/' + 
          LowerCase(E.ErrorCode))
        .SetTitle(E.ClassName)
        .SetStatus(E.StatusCode)
        .SetDetail(E.Message)
        .SetInstance(Req.RawWebRequest.PathInfo)
        .SendTo(Res);
    end;

    on E: Exception do
    begin
      { FALHA CATASTROFICA NAO TRATADA: Erro de Heap, Banco ou Codigo }
      vCorrelationId := 
        Res.RawWebResponse.GetCustomHeader('X-Correlation-ID');

      { Emissao de log com erro tecnico real para auditoria interna }
      WriteLn(Format('[CRITICAL-ERROR] %s | CorrID: %s | Falha: %s: %s',
        [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now),
         vCorrelationId,
         E.ClassName,
         E.Message]));

      { RESPOSTA CEGA SEGURA AO CLIENTE: Nunca exponha detalhes }
      TProblemDetails.CreateNew
        .SetType('https://api.connectos.com/erros/erro-interno')
        .SetTitle('Erro Interno de Servidor')
        .SetStatus(500)
        .SetDetail('Ocorreu uma falha inesperada no processamento. ' +
                   'Informe o identificador de correlacao ao suporte.')
        .SetInstance(Req.RawWebRequest.PathInfo)
        .SendTo(Res);
    end;
  end;
end;

end.
```

> **Atenção Thread-Safety:**  
> Ao capturar uma exceção imprevista de sistema (`on E: Exception do`), jamais permita que dados de conexão do banco de dados Firebird (como nome de arquivo `.fdb`, usuário `SYSDBA` ou parâmetros de consulta SQL) sejam passados para a propriedade `SetDetail`. Em produção, informe uma mensagem estática e devolva apenas o `X-Correlation-ID`. O diagnóstico detalhado deve ser consultado exclusivamente pela equipe de operações nos logs do `journalctl`.

---

### Passo 4: Atualizando o Ponto de Entrada: ConnectOSApi.lpr

No programa principal, a ordem de registro dos middlewares é sagrada:
1. `TMiddlewareGlobalExceptionHandler` deve ser o **primeiro** (para encapsular tudo).
2. `TMiddlewareCORS` deve ser o **segundo** (para responder preflights precocemente).
3. `Jhonson` e middlewares de telemetria seguem na sequência.

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
  Middlewares.GlobalExceptionHandler,
  Middlewares.CORS,
  Middlewares.CorrelationId,
  Middlewares.Logger,
  Middlewares.RateLimit,
  Controllers.Ping,
  Controllers.Clientes;

procedure DoOnListen;
begin
  WriteLn('----------------------------------------------------');
  WriteLn('  CONNECT OS API - SEGURANCA E EXCECOES ATIVAS      ');
  WriteLn('  - Exception Handler: Ativo (RFC 7807 Fail-Safe)   ');
  WriteLn('  - CORS Manager     : Ativo (Suporte a Preflight)  ');
  WriteLn('  - Jhonson JSON     : Ativo                        ');
  WriteLn('  - Correlation-ID   : Ativo                        ');
  WriteLn('  - Rate Limiter     : Ativo                        ');
  WriteLn('  Ouvindo em : http://0.0.0.0:' + IntToStr(THorse.Port));
  WriteLn('----------------------------------------------------');
end;

var
  vPorta: Word;
begin
  vPorta := StrToIntDef(GetEnvironmentVariable('PORT'), 9000);
  THorse.Port := vPorta;

  { Configuracao de CORS para aplicacao SPA }
  TMiddlewareCORS.Configurar('*');

  { 1. SENTINELA GLOBAL DE EXCECOES (PRIMEIRO OBRIGATORIO) }
  THorse.Use(@TMiddlewareGlobalExceptionHandler.Middleware);

  { 2. CONTROLE DE CORS E PREFLIGHT }
  THorse.Use(@TMiddlewareCORS.Middleware);

  { 3. TRADUTOR JSON E AUDITORIA }
  THorse.Use(Jhonson);
  THorse.Use(@TMiddlewareCorrelationId.Middleware);
  THorse.Use(@TMiddlewareLogger.Middleware);
  THorse.Use(@TMiddlewareRateLimit.Middleware);

  { 4. ROTAS DA APLICACAO }
  TControllersPing.Registry;
  TControllersClientes.Registry;

  THorse.Listen(@DoOnListen);
end.
```

---

## 4. TESTANDO O ENDPOINT

Vamos validar a resolução de requisições Preflight `OPTIONS` e o comportamento do interceptador global diante de falhas controladas e acidentais com `curl`.

### Teste 1: Validação do Preflight CORS (OPTIONS)

Simule a requisição preliminar que um navegador emite ao se comunicar com a API:

```bash
curl -i -X OPTIONS http://localhost:9000/api/v1/clientes \
     -H "Origin: https://app.conectos.com" \
     -H "Access-Control-Request-Method: POST" \
     -H "Access-Control-Request-Headers: X-Tenant-ID, Content-Type"
```

**Resposta Emitida pelo Middleware de CORS (204 No Content):**

```http
HTTP/1.1 204 No Content
Access-Control-Allow-Origin: https://app.conectos.com
Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS
Access-Control-Allow-Headers: Content-Type, Authorization,
  X-Tenant-ID, X-Correlation-ID
Access-Control-Allow-Credentials: true
Access-Control-Max-Age: 86400
Date: Mon, 23 Nov 2026 12:10:00 GMT
Server: fphttpserver
```

O preflight respondeu instantaneamente em **204 No Content**, autorizando a origem da SPA e liberando o navegador para realizar a chamada real.

---

### Teste 2: Testando o Tratamento de Exceções de Domínio (422)

Para testar o interceptador de exceções, criaremos uma rota transitória de teste que dispara `raise EBusinessException.Create('Cliente bloqueado no Serasa')`:

```bash
curl -i http://localhost:9000/api/v1/teste/falha-negocio
```

**Resposta Traduzida pelo Interceptador Global (422 Unprocessable Entity):**

```http
HTTP/1.1 422 Unprocessable Entity
X-Correlation-ID: 99a1b2c3-4d5e-6f7a-8b9c-0d1e2f3a4b5c
Content-Type: application/problem+json; charset=utf-8
Content-Length: 260

{"type":"https://api.connectos.com/erros/regra_negocio_violada",
 "title":"EBusinessException",
 "status":422,
 "detail":"Cliente bloqueado no Serasa",
 "instance":"/api/v1/teste/falha-negocio"}
```

A camada de negócio simplesmente disparou um `raise` nativo do Object Pascal. O interceptador global capturou o erro, associou o código 422 e construiu o documento RFC 7807 sem nenhum bloco `try..except` no controlador.

---

### Teste 3: Testando a Blindagem contra Erros Catastróficos (500)

Simule um erro grave inesperado de programação, como uma divisão por zero (`raise EDivByZero.Create('Division by zero')`):

```bash
curl -i http://localhost:9000/api/v1/teste/divisao-zero
```

**Log Interno Crítico Emitido no Terminal do Servidor:**

```text
[CRITICAL-ERROR] 2026-11-23 12:10:45
CorrID: d4e5f6a7-1b2c-3d4e-5f6a-7b8c9d0e1f2a | Falha: EDivByZero
```

**Resposta Cega e Segura Retornada ao Cliente Externo (500):**

```http
HTTP/1.1 500 Internal Server Error
X-Correlation-ID: d4e5f6a7-1b2c-3d4e-5f6a-7b8c9d0e1f2a
Content-Type: application/problem+json; charset=utf-8
Content-Length: 310

{"type":"https://api.connectos.com/erros/erro-interno",
 "title":"Erro Interno de Servidor",
 "status":500,
 "detail":"Ocorreu uma falha inesperada no processamento. "
          "Informe o correlation-id ao suporte.",
 "instance":"/api/v1/teste/divisao-zero"}
```

Nenhum detalhe da pilha de execução ou da vulnerabilidade foi exposto ao atacante externo, garantindo conformidade rigorosa com normas de segurança (OWASP API Security Top 10).

---

## 5. ARMADILHAS COMUNS E TROUBLESHOOTING NO FPC/LAZARUS

---

### Armadilha 1: Registrar o Interceptador de Exceções na Posição Incorreta

**Sintoma:** Ao ocorrer uma exceção dentro de um middleware (como autenticação ou serialização), o servidor quebra e o cliente recebe uma página de erro crua da FCL ou conexão abortada.

**Causa Raiz:** O middleware de exceções foi registrado após outros middlewares que podem falhar:

```pascal
{ EQUIVOCO GRAVE: Middlewares anteriores estao desprotegidos }
THorse.Use(Jhonson);
{ Tarde demais: interceptador apos outros middlewares }
THorse.Use(@TMiddlewareGlobalExceptionHandler.Middleware);
```

**Solução:** O sentinela global de exceções deve ser rigorosamente a **primeiríssima** instrução `THorse.Use` do servidor.

---

### Armadilha 2: Conflito entre Access-Control-Allow-Origin: * e Credenciais

**Sintoma:** O navegador recusa chamadas autenticadas exibindo:

```text
The 'Access-Control-Allow-Origin' header must not be '*'
when credentials mode is 'include'.
```

**Causa Raiz:** Uso indiscriminado do curinga `*` quando a requisição transmite cookies ou credenciais de sessão.

**Solução:** Conforme demonstrado em `Middlewares.CORS.pas`, capture o cabeçalho `Origin` da requisição e reflita-o explicitamente no `Access-Control-Allow-Origin`.

---

### Armadilha 3: Destruição Incorreta da Instância da Exceção

**Sintoma:** O compilador emite avisos de vazamento de memória com o uso de `HeapTrc`.

**Causa Raiz:** Tentar invocar `E.Free;` dentro de um bloco `except on E: Exception do`.

**Solução:** No Object Pascal, o runtime do Free Pascal assume automaticamente a gerência do ciclo de vida da instância `E` no bloco `on E: Exception do`. O compilador destrói a exceção assim que o bloco `except` é concluído. **Nunca** invoque `E.Free` manualmente.

---

## 6. RESUMO EXECUTIVO E CHECKLIST DE REVISÃO

### Matriz de Mapeamento de Exceções para Códigos HTTP

| Classe de Exceção | Código HTTP | Significado RFC 7807 | Exemplo de Aplicação |
| :--- | :--- | :--- | :--- |
| **`EAppException`** | `400` | `Parametro Invalido` | Dados malformados ou incompletos. |
| **`EUnauthorizedException`**| `401` | `Nao Autorizado` | Token JWT ausente ou expirado. |
| **`EForbiddenException`** | `403` | `Acesso Proibido` | Usuário sem perfil de acesso. |
| **`ENotFoundException`** | `404` | `Recurso Nao Encontrado` | Identificador não cadastrado no banco. |
| **`EConflictException`** | `409` | `Conflito de Estado` | CNPJ já vinculado a outra conta. |
| **`EBusinessException`** | `422` | `Regra Negocio Violada`| Limite de crédito excedido no pedido. |
| **`Exception` (Genérica)**| `500` | `Erro Interno Servidor` | Divisão por zero, falha de driver. |

---

### Checklist de Revisão e Auditoria Técnica

Antes de avançar para o Módulo 08, audite a conformidade dos itens:

- [ ] **Preflight OPTIONS:** O middleware de CORS responde a requisições `OPTIONS` com status `204 No Content` e encerra a cadeia (*short-circuit*).
- [ ] **Posicionamento de Sentinela:** O middleware de tratamento global de exceções é o primeiríssimo componente registrado no `THorse.Use`.
- [ ] **Desacoplamento de Domínio:** As classes de domínio e serviços lançam exceções derivadas de `EAppException`, sem referências a código HTTP.
- [ ] **Blindagem em Produção:** Exceções imprevistas geram log técnico com `Correlation-ID` no servidor e retornam uma mensagem cega e protegida para o cliente externo.
- [ ] **Ciclo de Vida de Exceções:** Nenhuma instância de exceção é destruída manualmente dentro de blocos `except`.

Com o pipeline de middlewares devidamente protegido por CORS e blindado contra falhas, estamos prontos para avançar para o **Módulo 08**, onde construiremos o sistema completo de autenticação e segurança stateless com **JSON Web Tokens (JWT)** e **Refresh Tokens** persistidos no Firebird 5.0.
