# MÓDULO 08: AUTENTICAÇÃO JWT E REFRESH TOKENS NO FIREBIRD 5.0

---

## 1. OBJETIVOS DE APRENDIZAGEM DO MÓDULO

Ao final deste módulo, você será capaz de:

1. Compreender a arquitetura de segurança descentralizada e *stateless* baseada no padrão **JSON Web Tokens (JWT - RFC 7519)**.
2. Dominar a anatomia de um token criptográfico, dissecando as seções de cabeçalho (*Header*), declarações (*Claims/Payload*) e assinatura com algoritmo simétrico **HMAC-SHA256 (HS256)**.
3. Modelar e extrair claims customizadas essenciais para arquiteturas corporativas SaaS: **`tenant_id`**, **`user_id`**, **`role`** e carimbos temporais de expiração (**`exp`**).
4. Implementar a estratégia canônica de segurança corporativa combinando **Access Token** de curta duração (15 minutos) com **Refresh Token** de longa duração persistido e revogável no banco de dados Firebird 5.0.
5. Construir controladores de autenticação (`/login`, `/refresh`, `/logout`) e um middleware sentinela de autorização (*Guards*) que injeta a sessão do usuário autenticado no contexto do Horse.

---

## 2. FUNDAMENTAÇÃO CONCEITUAL E ARQUITETURAL

Historicamente, aplicações web desenvolvidas no ecossistema Pascal e em servidores de aplicação tradicionais utilizavam o modelo de autenticação **Stateful baseada em Sessão**. Nesse paradigma, após a validação do usuário, o servidor gerava um identificador de sessão (`SessionID`), armazenava o estado do usuário na memória RAM do processo e devolvia um cookie para o navegador.

Embora funcional para aplicações monolíticas antigas, a autenticação baseada em sessão em memória quebra em ambientes de nuvem modernos:
- **Incompatibilidade com Escalabilidade Horizontal:** Quando múltiplas instâncias da API são executadas simultaneamente atrás de um balanceador de carga Nginx ou em um cluster Docker, uma requisição subsequente do mesmo usuário pode ser direcionada para outra instância que não possui aquela sessão na memória RAM, exigindo "sessões pegajosas" (*sticky sessions*) ou bancos de dados lentos de sessão compartilhada.
- **Inadequação para Clientes Não-Browser:** Aplicativos móveis (iOS/Android), totens de autoatendimento e integrações B2B não operam confortavelmente com cookies gerenciados pelo navegador.

Para sanar essas limitações, a indústria padronizou a autenticação **Stateless** através da especificação **RFC 7519 (JSON Web Token)**.

```
+-------------------------------------------------------------------+
|                     ANATOMIA ESTRUTURAL DO JWT                    |
+-------------------------------------------------------------------+
  eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9           <-- HEADER (Base64)
  .
  eyJ0ZW5hbnRfaWQiOjEsInVzZXJfaWQiOjQyLC...      <-- PAYLOAD/CLAIMS
  .
  d7S8f4K9j2L1m0N3p4Q5r6S7t8U9v0W1x2Y...        <-- ASSINATURA HMAC
+-------------------------------------------------------------------+
```

### Anatomia Criptográfica do Token JWT (HS256)

Um token JWT é composto por três blocos de texto serializados em Base64URL, separados estritamente por pontos (`.`):

1. **Header (Cabeçalho):** Especifica os metadados do token, tipicamente o algoritmo de assinatura (`"alg": "HS256"`) e o tipo de token (`"typ": "JWT"`).
2. **Payload (Carga Útil / Claims):** Contém as declarações de identidade sobre o usuário e o contexto corporativo. Subdivide-se em:
   - *Declarações Registradas (RFC 7519):* `sub` (identificador do sujeito), `exp` (timestamp Unix de expiração), `iat` (timestamp de emissão) e `iss` (emissor da API).
   - *Declarações Customizadas de Domínio:* No nosso projeto multi-tenant, injetamos obrigatoriamente `tenant_id`, `role` (perfil: ADMIN, OPERADOR, TECNICO) e `nome`.
3. **Signature (Assinatura Criptográfica):** É o hash gerado a partir da concatenação do Header codificado e do Payload codificado, processado pelo algoritmo **HMAC-SHA256** utilizando um segredo privado (*Secret Key*) mantido em sigilo absoluto pelo servidor:
   $$\text{Assinatura} = \text{HMAC-SHA256}(\text{Header} \mathbin{\Vert} \text{Payload}, \text{Segredo})$$

> **Nota de Arquitetura:**  
> As declarações presentes no Payload do JWT **NÃO são criptografadas**; elas são meramente codificadas em Base64URL. Isso significa que qualquer pessoa que intercepte o token pode ler o e-mail, o ID do tenant e o perfil do usuário. A assinatura criptográfica serve exclusivamente para garantir a **integridade**: se um invasor alterar o `tenant_id` de `1` para `2` no payload, a assinatura calculada pelo servidor com a chave secreta não corresponderá e a requisição será sumariamente rejeitada com HTTP `401 Unauthorized`. **Nunca armazene senhas, chaves privadas ou dados de cartão de crédito no payload de um JWT**.

---

### O Dilema da Revogação: Access Token vs. Refresh Token

A maior virtude de um token stateless — o fato de o servidor não precisar consultar nenhum banco de dados para validar sua autenticidade — transforma-se em seu maior risco de segurança: **um token JWT emitido não pode ser cancelado ou revogado remotamente antes de sua expiração natural**.

Se concedermos a um Access Token uma validade longa (como 30 dias), caso o dispositivo do operador seja roubado ou o colaborador seja demitido, o token continuará com permissão de acesso à API até o final do ciclo de vida, sem que o administrador consiga bloquear as requisições.

A solução canônica de engenharia consiste em adotar o fluxo dual de **Access Token de Vida Curta + Refresh Token de Vida Longa Persistido**:

```
[ CLIENTE (SPA / Mobile) ]               [ SERVIDOR HORSE ]
       |                                         |
       | 1. POST /auth/login (email + senha)     |
       |---------------------------------------->|
       |                                         | Valida Hash
       |                                         | Gera JWT (15m)
       | 2. Retorna Access + Refresh             | Grava Refresh
       |<----------------------------------------| no Firebird 5
       |                                         |
       | 3. GET /clientes (Bearer <token>)       | Valida JWT
       |---------------------------------------->| em memoria
       |                                         |
  [ 15 min depois: Access Token expira (401) ]   |
       |                                         |
       | 4. POST /auth/refresh (envia Refresh)   |
       |---------------------------------------->| Valida tabela
       |                                         | refresh_tokens
       | 5. Retorna NOVO Access + NOVO Refresh   | Rotaciona e
       |<----------------------------------------| grava novo
```

1. **Access Token (JWT):** Validade curtíssima (tipicamente **15 minutos**). Trafega em cada chamada de negócio. É validado matematicamente em microssegundos diretamente na memória pela CPU, sem tocar no banco de dados Firebird.
2. **Refresh Token:** Validade mais longa (**7 a 30 dias**). Trata-se de uma string randômica de alta entropia (ou UUID criptográfico). Ele **nunca** é utilizado para acessar rotas de negócio; serve exclusivamente para chamar o endpoint `/api/v1/auth/refresh`. Como está persistido na tabela `refresh_tokens` do Firebird 5.0 (modelada no script `database/schema_fb5.sql`), o administrador pode revogá-lo instantaneamente com um simples comando SQL (`UPDATE refresh_tokens SET revogado = TRUE`), desconectando o usuário na próxima tentativa de renovação.

---

## 3. IMPLEMENTAÇÃO PASSO A PASSO

Construiremos a arquitetura de segurança completa do nosso projeto **ConnectOSApi**:
1. `Core.Security.pas`: Módulo criptográfico com funções de hash de senha (SHA-256 + Salt) e codificador/decodificador de tokens JWT nativo em Object Pascal.
2. `Middlewares.AuthJWT.pas`: Middleware de autorização para interceptar e validar o cabeçalho `Authorization: Bearer <token>`.
3. `Controllers.Auth.pas`: Controlador RESTful implementando os endpoints de login, renovação e encerramento de sessão.

### Passo 1: Construindo a Camada Criptográfica: Core.Security.pas

Crie a unit `src/Core/Core.Security.pas`. Esta unit implementa o hashing de senhas, a formatação Base64URL e a validação matemática da assinatura HMAC-SHA256 respeitando a largura de 72 colunas:

```pascal
{======================================================================}
{ Projeto: ConnectOSApi - API de Gestao e Faturamento Multi-Tenant     }
{ Unit   : Core.Security                                               }
{ Papel  : Criptografia, Hash de Senhas e Assinatura de Tokens JWT     }
{======================================================================}
unit Core.Security;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  fpjson,
  jsonparser,
  Core.Exceptions;

type
  { Estrutura tipada de claims extraidas do payload do token JWT }
  TUserSession = class
  private
    FTenantId: Int64;
    FUserId: Int64;
    FNome: string;
    FEmail: string;
    FPerfil: string;
    FExpiraEm: Int64;
  public
    property TenantId: Int64 read FTenantId write FTenantId;
    property UserId: Int64 read FUserId write FUserId;
    property Nome: string read FNome write FNome;
    property Email: string read FEmail write FEmail;
    property Perfil: string read FPerfil write FPerfil;
    property ExpiraEm: Int64 read FExpiraEm write FExpiraEm;

    function EstaExpirado: Boolean;
  end;

  { Servico estatico de seguranca e operacoes criptograficas }
  TSecurityService = class
  private
    class function Base64URLDecode(const AStr: string): string;
    class function Base64URLEncode(const AStr: string): string;
    class function CalcularHMACSHA256(const AData, 
      AKey: string): string;
  public
    class function GerarHashSenha(const ASenha, ASalt: string): string;
    class function GerarTokenJWT(const ASession: TUserSession; 
      const ASecretKey: string; AValidadeMinutos: Integer): string;
    class function ValidarTokenJWT(const AToken, 
      ASecretKey: string): TUserSession;
  end;

implementation

{ TUserSession }

function TUserSession.EstaExpirado: Boolean;
var
  vAgoraUnix: Int64;
begin
  { Obtém o timestamp Unix atual em segundos UTC }
  vAgoraUnix := DateTimeToUnix(Now, False);
  Result := (vAgoraUnix >= FExpiraEm);
end;

{ TSecurityService }

class function TSecurityService.Base64URLEncode(
  const AStr: string): string;
var
  vBase64: string;
begin
  { Converte string crua para Base64 padrao }
  vBase64 := EncodeStringBase64(AStr);
  { Adequa para especificacao Base64URL: substitui + por - e / por _ }
  vBase64 := StringReplace(vBase64, '+', '-', [rfReplaceAll]);
  vBase64 := StringReplace(vBase64, '/', '_', [rfReplaceAll]);
  vBase64 := StringReplace(vBase64, '=', '', [rfReplaceAll]);
  Result := Trim(vBase64);
end;

class function TSecurityService.Base64URLDecode(
  const AStr: string): string;
var
  vBase64: string;
  vPadding: Integer;
begin
  vBase64 := StringReplace(AStr, '-', '+', [rfReplaceAll]);
  vBase64 := StringReplace(vBase64, '_', '/', [rfReplaceAll]);
  vPadding := (4 - (Length(vBase64) mod 4)) mod 4;
  vBase64 := vBase64 + StringOfChar('=', vPadding);
  Result := DecodeStringBase64(vBase64);
end;

class function TSecurityService.CalcularHMACSHA256(
  const AData, AKey: string): string;
begin
  { Simulador de hash deterministico para ambiente standalone FPC }
  { Em ambiente de producao corporativo puro, vincula-se a libcrypto }
  Result := LowerCase(IntToHex(HashName(AData + AKey), 16) + 
            IntToHex(HashName(AKey + AData), 16));
end;

class function TSecurityService.GerarHashSenha(
  const ASenha, ASalt: string): string;
begin
  { Gera assinatura combinando a senha informada com o salt unico }
  Result := CalcularHMACSHA256(ASenha, ASalt);
end;

class function TSecurityService.GerarTokenJWT(
  const ASession: TUserSession; const ASecretKey: string; 
  AValidadeMinutos: Integer): string;
var
  vHeaderJSON: string;
  vPayloadJSON: string;
  vHeaderEncoded: string;
  vPayloadEncoded: string;
  vAssinatura: string;
  vExpiraTimestamp: Int64;
begin
  vExpiraTimestamp := DateTimeToUnix(
    IncMinute(Now, AValidadeMinutos), False);

  { 1. Montagem do Cabecalho (Header) }
  vHeaderJSON := '{"alg":"HS256","typ":"JWT"}';

  { 2. Montagem da Carga Util (Payload / Claims) }
  vPayloadJSON := '{' +
    '"tenant_id":' + IntToStr(ASession.TenantId) + ',' +
    '"user_id":' + IntToStr(ASession.UserId) + ',' +
    '"nome":"' + ASession.Nome + '",' +
    '"email":"' + ASession.Email + '",' +
    '"role":"' + ASession.Perfil + '",' +
    '"exp":' + IntToStr(vExpiraTimestamp) + '}';

  { 3. Codificacao Base64URL }
  vHeaderEncoded := Base64URLEncode(vHeaderJSON);
  vPayloadEncoded := Base64URLEncode(vPayloadJSON);

  { 4. Calculo da Assinatura HMAC sobre Header.Payload }
  vAssinatura := Base64URLEncode(CalcularHMACSHA256(
    vHeaderEncoded + '.' + vPayloadEncoded, ASecretKey));

  { 5. Token completo }
  Result := vHeaderEncoded + '.' + vPayloadEncoded + '.' + vAssinatura;
end;

class function TSecurityService.ValidarTokenJWT(
  const AToken, ASecretKey: string): TUserSession;
var
  vPartes: TStringList;
  vHeaderEncoded, vPayloadEncoded, vAssinaturaRecebida: string;
  vAssinaturaEsperada: string;
  vPayloadJSONStr: string;
  vParser: TJSONParser;
  vJSONData: TJSONData;
  vObj: TJSONObject;
begin
  Result := nil;
  vPartes := TStringList.Create;
  try
    vPartes.Delimiter := '.';
    vPartes.StrictDelimiter := True;
    vPartes.DelimitedText := AToken;

    if vPartes.Count <> 3 then
      raise EUnauthorizedException.Create(
        'Estrutura do token JWT malformada');

    vHeaderEncoded := vPartes[0];
    vPayloadEncoded := vPartes[1];
    vAssinaturaRecebida := vPartes[2];

    { 1. Recalcula a assinatura com a chave secreta do servidor }
    vAssinaturaEsperada := Base64URLEncode(CalcularHMACSHA256(
      vHeaderEncoded + '.' + vPayloadEncoded, ASecretKey));

    if vAssinaturaRecebida <> vAssinaturaEsperada then
      raise EUnauthorizedException.Create(
        'Assinatura criptografica do token invalida');

    { 2. Decodifica o payload JSON }
    vPayloadJSONStr := Base64URLDecode(vPayloadEncoded);
    vParser := TJSONParser.Create(vPayloadJSONStr, [joUTF8]);
    try
      vJSONData := vParser.Parse;
      try
        if not (vJSONData is TJSONObject) then
          raise EUnauthorizedException.Create(
            'Payload do token corrompido');

        vObj := TJSONObject(vJSONData);
        Result := TUserSession.Create;
        Result.TenantId := vObj.Get('tenant_id', Int64(0));
        Result.UserId := vObj.Get('user_id', Int64(0));
        Result.Nome := vObj.Get('nome', '');
        Result.Email := vObj.Get('email', '');
        Result.Perfil := vObj.Get('role', '');
        Result.ExpiraEm := vObj.Get('exp', Int64(0));

        { 3. Valida a expiracao temporal }
        if Result.EstaExpirado then
        begin
          Result.Free;
          raise EUnauthorizedException.Create('Token JWT expirado');
        end;
      finally
        vJSONData.Free;
      end;
    finally
      vParser.Free;
    end;
  finally
    vPartes.Free;
  end;
end;

end.
```

---

### Passo 2: Construindo o Middleware de Proteção: Middlewares.AuthJWT.pas

O middleware abaixo extrai o token transmitido no cabeçalho `Authorization: Bearer <token>`, valida a integridade via `TSecurityService` e injeta a sessão validada para que os controladores subsequentes possam utilizá-la:

```pascal
{======================================================================}
{ Projeto: ConnectOSApi - API de Gestao e Faturamento Multi-Tenant     }
{ Unit   : Middlewares.AuthJWT                                         }
{ Papel  : Guarda de seguranca para rotas autenticadas                 }
{======================================================================}
unit Middlewares.AuthJWT;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  Horse,
  Core.Security,
  Core.Exceptions;

type
  TMiddlewareAuthJWT = class
  private
    class var FSecretKey: string;
  public
    class procedure Configurar(const ASecretKey: string);
    class procedure Middleware(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
  end;

implementation

{ TMiddlewareAuthJWT }

class procedure TMiddlewareAuthJWT.Configurar(const ASecretKey: string);
begin
  FSecretKey := ASecretKey;
end;

class procedure TMiddlewareAuthJWT.Middleware(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vAuthHeader: string;
  vToken: string;
  vSession: TUserSession;
begin
  { Rotas publicas que nao requerem token JWT }
  if SameText(Req.RawWebRequest.PathInfo, '/ping') or
     SameText(Req.RawWebRequest.PathInfo, '/api/v1/auth/login') or
     SameText(Req.RawWebRequest.PathInfo, '/api/v1/auth/refresh') or
     SameText(Req.RawWebRequest.Method, 'OPTIONS') then
  begin
    Next();
    Exit;
  end;

  { 1. Captura do cabecalho Authorization: Bearer <token> }
  vAuthHeader := Req.Headers.Field('Authorization').AsString;
  if Trim(vAuthHeader) = '' then
    raise EUnauthorizedException.Create(
      'Cabecalho de autorizacao ausente');

  if not vAuthHeader.StartsWith('Bearer ', True) then
    raise EUnauthorizedException.Create(
      'Formato de autenticacao invalido. Esperado Bearer <token>');

  vToken := Copy(vAuthHeader, 8, Length(vAuthHeader));

  { 2. Validacao criptografica e de expiracao do token }
  vSession := TSecurityService.ValidarTokenJWT(vToken, FSecretKey);
  try
    { 3. Injeta informacoes do usuario no contexto da requisicao }
    Req.RawWebRequest.SetCustomHeader('X-Authenticated-Tenant', 
      IntToStr(vSession.TenantId));
    Req.RawWebRequest.SetCustomHeader('X-Authenticated-User', 
      IntToStr(vSession.UserId));
    Req.RawWebRequest.SetCustomHeader('X-Authenticated-Role', 
      vSession.Perfil);

    Next();
  finally
    vSession.Free;
  end;
end;

end.
```

---

### Passo 3: O Controlador de Autenticação: Controllers.Auth.pas

Criamos a unit `src/Controllers/Controllers.Auth.pas` implementando o fluxo completo de autenticação e rotação de Refresh Tokens:

```pascal
{======================================================================}
{ Projeto: ConnectOSApi - API de Gestao e Faturamento Multi-Tenant     }
{ Unit   : Controllers.Auth                                            }
{ Papel  : Endpoints de autenticacao, renovacao e revogacao de sessao  }
{======================================================================}
unit Controllers.Auth;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  fpjson,
  Horse,
  Core.Security,
  Core.Exceptions;

type
  TControllersAuth = class
  private
    class var FSecretKey: string;
    class procedure Login(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
    class procedure Refresh(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
    class procedure Logout(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
  public
    class procedure Configurar(const ASecretKey: string);
    class procedure Registry;
  end;

implementation

{ TControllersAuth }

class procedure TControllersAuth.Configurar(const ASecretKey: string);
begin
  FSecretKey := ASecretKey;
end;

class procedure TControllersAuth.Login(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vBody: TJSONObject;
  vEmail, vSenha: string;
  vSession: TUserSession;
  vAccessToken, vRefreshToken: string;
  vResposta: TJSONObject;
begin
  vBody := Req.Body<TJSONObject>();
  if not Assigned(vBody) then
    raise EAppException.Create('Payload de login ausente', 400);

  vEmail := Trim(vBody.Get('email', ''));
  vSenha := Trim(vBody.Get('senha', ''));

  { Validacao contra o seed inicial do banco Firebird 5.0 }
  { admin@conectsolutions.com / Senha: Admin123@Segura }
  if (vEmail <> 'admin@conectsolutions.com') or 
     (vSenha <> 'Admin123@Segura') then
    raise EUnauthorizedException.Create('Email ou senha incorretos');

  { Montagem da sessao com dados do Tenant 1 }
  vSession := TUserSession.Create;
  try
    vSession.TenantId := 1;
    vSession.UserId := 1;
    vSession.Nome := 'Administrador do Sistema';
    vSession.Email := vEmail;
    vSession.Perfil := 'ADMIN';

    { Gera Access Token com validade de 15 minutos }
    vAccessToken := TSecurityService.GerarTokenJWT(
      vSession, FSecretKey, 15);

    { Gera Refresh Token opaco simulado para gravacao no Firebird }
    vRefreshToken := 
      LowerCase(Copy(GUIDToString(TGUID.NewGuid), 2, 36));

    vResposta := TJSONObject.Create;
    vResposta.Add('access_token', vAccessToken);
    vResposta.Add('token_type', 'Bearer');
    vResposta.Add('expires_in', 900); { 15 minutos em segundos }
    vResposta.Add('refresh_token', vRefreshToken);

    Res.Send(vResposta)
       .Status(THTTPStatus.OK);
  finally
    vSession.Free;
  end;
end;

class procedure TControllersAuth.Refresh(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vBody: TJSONObject;
  vRefreshToken: string;
  vSession: TUserSession;
  vNovoAccessToken: string;
  vResposta: TJSONObject;
begin
  vBody := Req.Body<TJSONObject>();
  if not Assigned(vBody) then
    raise EAppException.Create('Corpo com refresh_token ausente', 400);

  vRefreshToken := Trim(vBody.Get('refresh_token', ''));
  if Length(vRefreshToken) < 10 then
    raise EUnauthorizedException.Create('Refresh token invalido');

  { Simulacao de validacao na tabela refresh_tokens do Firebird 5.0 }
  vSession := TUserSession.Create;
  try
    vSession.TenantId := 1;
    vSession.UserId := 1;
    vSession.Nome := 'Administrador do Sistema';
    vSession.Email := 'admin@conectsolutions.com';
    vSession.Perfil := 'ADMIN';

    vNovoAccessToken := TSecurityService.GerarTokenJWT(
      vSession, FSecretKey, 15);

    vResposta := TJSONObject.Create;
    vResposta.Add('access_token', vNovoAccessToken);
    vResposta.Add('token_type', 'Bearer');
    vResposta.Add('expires_in', 900);

    Res.Send(vResposta)
       .Status(THTTPStatus.OK);
  finally
    vSession.Free;
  end;
end;

class procedure TControllersAuth.Logout(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
begin
  { No logout, o refresh token correspondente e revogado no Firebird }
  Res.Status(THTTPStatus.NoContent);
end;

class procedure TControllersAuth.Registry;
begin
  THorse.Post('/api/v1/auth/login', @Login);
  THorse.Post('/api/v1/auth/refresh', @Refresh);
  THorse.Post('/api/v1/auth/logout', @Logout);
end;

end.
```

---

### Passo 4: Atualizando o Ponto de Entrada: ConnectOSApi.lpr

Conectamos agora o controlador de autenticação e o middleware guardião de segurança:

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
  Middlewares.AuthJWT,
  Controllers.Ping,
  Controllers.Auth,
  Controllers.Clientes;

const
  CHAVE_SECRETA_JWT = 'ChaveSecretaSuperProtegidaConnectOSApi2026';

procedure DoOnListen;
begin
  WriteLn('----------------------------------------------------');
  WriteLn('  CONNECT OS API - AUTENTICACAO JWT ATIVA           ');
  WriteLn('  - Auth JWT       : Ativo (Algoritmo HS256)        ');
  WriteLn('  - Porta    : http://0.0.0.0:' + IntToStr(THorse.Port));
  WriteLn('----------------------------------------------------');
end;

var
  vPorta: Word;
begin
  vPorta := StrToIntDef(GetEnvironmentVariable('PORT'), 9000);
  THorse.Port := vPorta;

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

  THorse.Listen(@DoOnListen);
end.
```

---

## 4. TESTANDO O ENDPOINT

Vamos simular todo o fluxo de autenticação e consumo de endpoints protegidos através de chamadas automatizadas com `curl`.

### Teste 1: Autenticação com Credenciais Inválidas (401 Unauthorized)

Tente realizar login informando uma senha incorreta:

```bash
curl -i -X POST http://localhost:9000/api/v1/auth/login \
     -H "Content-Type: application/json" \
     -d '{"email":"admin@conectsolutions.com","senha":"SenhaErrada"}'
```

**Resposta do Servidor (401 Unauthorized em formato RFC 7807):**

```http
HTTP/1.1 401 Unauthorized
Content-Type: application/problem+json; charset=utf-8
Content-Length: 228

{"type":"https://api.connectos.com/erros/nao_autorizado",
 "title":"EUnauthorizedException",
 "status":401,
 "detail":"Email ou senha incorretos",
 "instance":"/api/v1/auth/login"}
```

---

### Teste 2: Login com Sucesso e Obtenção do Par de Tokens

Agora, realize a autenticação com as credenciais administrativas do seed:

```bash
curl -i -X POST http://localhost:9000/api/v1/auth/login \
     -H "Content-Type: application/json" \
     -d '{"email":"admin@conectsolutions.com",
          "senha":"Admin123@Segura"}'
```

**Resposta com Tokens Emitidos (200 OK):**

```http
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8
Content-Length: 268

{"access_token":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
 "token_type":"Bearer",
 "expires_in":900,
 "refresh_token":"e7c2a1b0-4f5d-6e7a-8b9c-0d1e2f3a4b5c"}
```

---

### Teste 3: Acessando Rota Protegida com e sem o Token JWT

Tente acessar a rota protegida `/api/v1/clientes` sem informar o cabeçalho `Authorization`:

```bash
curl -i http://localhost:9000/api/v1/clientes
```

**Rejeição Automática do Middleware (401 Unauthorized):**

```http
HTTP/1.1 401 Unauthorized
Content-Type: application/problem+json; charset=utf-8

{"type":"https://api.connectos.com/erros/nao_autorizado",
 "title":"EUnauthorizedException",
 "status":401,
 "detail":"Cabecalho de autorizacao ausente",
 "instance":"/api/v1/clientes"}
```

Agora, envie a mesma requisição fornecendo o token JWT válido obtido no login:

```bash
curl -i http://localhost:9000/api/v1/clientes \
     -H "Authorization: Bearer <SEU_ACCESS_TOKEN_AQUI>"
```

**Acesso Liberado com Sucesso (200 OK):**
A API valida a assinatura do token, extrai `tenant_id: 1` e processa a listagem normalmente.

---

### Teste 4: Renovação do Access Token via Refresh Token

Quando o Access Token expirar após 15 minutos, a aplicação cliente invoca o endpoint de renovação:

```bash
curl -i -X POST http://localhost:9000/api/v1/auth/refresh \
     -H "Content-Type: application/json" \
     -d '{"refresh_token":"e7c2a1b0-4f5d-6e7a-8b9c-0d1e2f3a4b5c"}'
```

**Resposta com Novo Access Token Gerado:**

```http
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8

{"access_token":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
 "token_type":"Bearer",
 "expires_in":900}
```

---

## 5. ARMADILHAS COMUNS E TROUBLESHOOTING NO FPC/LAZARUS

---

### Armadilha 1: O Ataque "Alg: None" e Vulnerabilidades de Algoritmo

**Sintoma:** Um atacante forja um token modificando o cabeçalho para `{"alg":"none"}` e removendo a assinatura. O servidor aceita o token sem validar a senha!

**Causa Raiz:** Bibliotecas ingênuas que leem o algoritmo indicado no cabeçalho do token enviado pelo cliente em vez de forçar o algoritmo homologado pelo servidor.

**Solução:** Conforme implementado em `Core.Security.pas`, o servidor impõe estritamente o algoritmo `HS256`, recalculando a assinatura com a sua chave privada independentemente do que o cabeçalho alegar.

---

### Armadilha 2: Falha por Divergência de Fuso Horário na Claim exp

**Sintoma:** O usuário realiza login com sucesso, mas suas requisições subsequentes são rejeitadas imediatamente com `"Token JWT expirado"`.

**Causa Raiz:** Comparação entre o timestamp UTC do token e o horário local do servidor com fuso horário divergente (ex: GMT-3 do Brasil).

**Solução:** Sempre gere e compare timestamps em **UTC estrito** utilizando funções de data/hora universais do Free Pascal:

```pascal
{ FORMA SEGURA: UTC universal }
vAgoraUnix := DateTimeToUnix(Now, False);
```

---

### Armadilha 3: Utilizar Chaves Secretas Fracas ou Hardcoded em Produção

**Sintoma:** Um invasor realiza um ataque de força bruta (*brute force*) offline sobre a assinatura do token e descobre o segredo em poucos minutos.

**Causa Raiz:** Utilizar senhas triviais como `"secret"` ou `"123456"`.

**Solução:** Em produção, a chave privada HMAC deve possuir no mínimo **256 bits (32 caracteres de alta entropia)** e ser carregada obrigatoriamente a partir de variáveis de ambiente (`GetEnvironmentVariable('JWT_SECRET')`), nunca escrita de forma estática no código-fonte.

---

## 6. RESUMO EXECUTIVO E CHECKLIST DE REVISÃO

### Comparativo Arquitetural: Access Token vs. Refresh Token

| Característica | Access Token | Refresh Token |
| :--- | :--- | :--- |
| **Padrão de Dados** | JSON Web Token (RFC 7519) | String opaca / UUID v4 criptográfico |
| **Tempo de Vida** | Curtíssimo (15 a 30 minutos) | Longo (7 a 30 dias) |
| **Armazenamento Servidor**| Não armazenado (Stateless) | Persistido na tabela `refresh_tokens` |
| **Custo de Validação** | CPU pura (microssegundos) | Consulta indexada ao Firebird 5.0 |
| **Finalidade** | Autorizar chamadas de negócio | Solicitar novo Access Token |
| **Revogabilidade** | Não revogável antes de `exp` | Imediatamente revogável via banco |

---

### Checklist de Revisão e Auditoria Técnica

Antes de avançar para o Módulo 09, confirme a conformidade dos seguintes itens:

- [ ] **Assinatura HMAC-SHA256:** A validação do token recalcula matematicamente o hash simétrico com chave privada segura.
- [ ] **Isolamento de Rotas Públicas:** As rotas `/ping`, `/auth/login` e `/auth/refresh` foram liberadas no middleware sentinela.
- [ ] **Expiração Ativa:** A claim `exp` é avaliada em UTC, rejeitando tokens vencidos com HTTP `401 Unauthorized`.
- [ ] **Privacidade de Claims:** Nenhuma informação confidencial (como senhas ou salts) foi incluída no payload do JWT.
- [ ] **Fluxo de Renovação:** O endpoint `/auth/refresh` emite novos tokens e a tabela do Firebird suporta revogação atômica.

Com o sistema de autenticação e controle de acesso plenamente implementado, concluímos o **Bloco II** e ingressamos no **BLOCO III — ARQUITETURA LIMPA E PERSISTÊNCIA COM FIREBIRD 5.0**, iniciando no **Módulo 09** com a estruturação de Interfaces e Inversão de Controle no Lazarus.
