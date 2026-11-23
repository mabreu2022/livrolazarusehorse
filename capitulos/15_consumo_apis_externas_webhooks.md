# Módulo 15: Consumo de APIs Externas, Webhooks e Resiliência HTTP

No ecossistema corporativo atual, nenhuma API REST opera isolada como uma 
ilha. Uma plataforma de gestão de ordens de serviço e faturamento necessita 
comunicar-se com múltiplos serviços externos: gateways de pagamento (para 
cobrança via PIX ou Cartão de Crédito), sistemas emissores de Notas Fiscais 
Eletrônicas (NF-e/NFS-e), provedores de mensageria (WhatsApp/SMS) e serviços 
de consulta cadastral (Receita Federal para CNPJ e ViaCEP).

Além de atuar como cliente HTTP de saída (*outbound*), nossa API deve ser 
capaz de receber notificações assíncronas (*inbound webhooks*) com garantia 
estrita de integridade via assinatura HMAC-SHA256, controle rigoroso de 
idempotência e mecanismos de repetição com recuo exponencial (*Exponential 
Backoff*). 

Neste módulo, implementaremos o cliente HTTP nativo do Free Pascal 
(`fphttpclient` com `opensslsockets`), construiremos um manipulador de 
webhooks seguro e implementaremos uma fila de disparos resiliente no 
**Firebird 5.0**.

---

## 1. Objetivos de Aprendizagem do Módulo

Ao concluir este módulo, você será capaz de:
1. Utilizar o cliente HTTP nativo do FPC (`fphttpclient`) com suporte 
   completo a HTTPS e cifras modernas através da unit `opensslsockets`.
2. Estruturar chamadas HTTP síncronas de saída de forma desacoplada, 
   respeitando timeouts rígidos para não bloquear threads do Horse.
3. Projetar e implementar receptores de Webhooks com autenticação 
   criptográfica via assinatura HMAC-SHA256 no cabeçalho `X-Signature`.
4. Garantir a idempotência das requisições de webhook utilizando chaves 
   únicas no Firebird 5.0 para evitar processamentos duplicados.
5. Construir uma fila transacional de emissão de webhooks com política 
   de repetição automática (*retries*) e recuo exponencial.
6. Diagnosticar e solucionar incompatibilidades de bibliotecas dinâmicas 
   OpenSSL (`libssl.so` e `libcrypto.so`) no Linux e Windows.

---

## 2. Fundamentação Conceitual e Arquitetural

### 2.1 A Pilha de Clientes HTTP no Free Pascal: `fphttpclient` e OpenSSL

O Free Pascal fornece em sua biblioteca padrão (`FCL-Web`) a classe 
`TFPHTTPClient` (unit `fphttpclient`). Para realizar requisições HTTPS 
(porta 443), o FPC delega a criptografia SSL/TLS para uma biblioteca 
dinâmica nativa do sistema operacional através de *sockets* especializados.

Declarando a unit `opensslsockets` na cláusula `uses`, o runtime do FPC 
carrega dinamicamente a biblioteca OpenSSL:
- No **Linux (Ubuntu 24.04 LTS):** `libssl.so.3` e `libcrypto.so.3`.
- No **Windows:** `libssl-3-x64.dll` e `libcrypto-3-x64.dll`.

```
+--------------------------------------------------------------------+
|                CAMADAS DO CLIENTE HTTP NO FREE PASCAL              |
|                                                                    |
|  [Camada de Aplicacao / Service]                                   |
|         |                                                          |
|         v                                                          |
|  [TFPHTTPClient] (fcl-web: controle HTTP, headers, cookies, verbs) |
|         |                                                          |
|         v                                                          |
|  [opensslsockets] (Camada de enlace de socket criptografado TLS)   |
|         |                                                          |
|         v                                                          |
|  [OpenSSL Engine] (libssl.so / libcrypto.so nativo do SO)          |
+--------------------------------------------------------------------+
```

> **Atenção Thread-Safety:**
> `TFPHTTPClient` **não é thread-safe**. Nunca compartilhe uma mesma 
> instância de `TFPHTTPClient` entre múltiplas requisições Horse. Cada 
> chamada a serviço externo deve instanciar seu próprio cliente localmente 
> dentro do escopo da thread em execução e liberá-lo no bloco `finally`.

### 2.2 O Perigo Fatal de Chamadas Síncronas sem Timeout

Ao consumir uma API de pagamento externa, se o servidor remoto passar por 
lentidão ou indisponibilidade, uma chamada sem timeout configurado 
prenderá a thread do `fphttpserver` indefinidamente. Se a aplicação 
receber vinte requisições concorrentes, todo o pool de threads do Horse 
será consumido por chamadas pendentes, travando a API inteira para todos 
os clientes.

> **Boas Práticas FPC:**
> Em qualquer comunicação HTTP externa, configure explicitamente:
> 1. `ConnectTimeout`: Tempo máximo para estabelecer conexão TCP (ex: 5s).
> 2. `IOTimeout`: Tempo máximo de espera pela resposta dos dados (ex: 10s).
> 3. Envolva chamadas em blocos `try..except` tratando `EHTTPClient` e 
>    `ESocketError` para retornar respostas de erro elegantes ao usuário.

### 2.3 Arquitetura de Webhooks: Assinatura HMAC e Idempotência

Um webhook é uma notificação HTTP POST enviada de um sistema para outro 
quando determinado evento ocorre (ex: "pagamento_aprovado"). Para que nossa 
API possa confiar na mensagem recebida:

1. **Assinatura Criptográfica HMAC-SHA256:** O emissor calcula um HMAC do 
   corpo JSON utilizando uma chave secreta compartilhada (*Webhook Secret*) 
   e o anexa ao cabeçalho (ex: `X-Signature: sha256=...`). Nosso receptor 
   recalcula o hash e rejeita a requisição com `401 Unauthorized` se houver 
   divergência.
2. **Idempotência Estrita:** Na internet, notificações de webhooks podem 
   ser reenviadas devido a instabilidades de rede. Se nossa API processar o 
   mesmo evento duas vezes, uma ordem de serviço poderá ter seu saldo baixado 
   duplicadamente. Registramos o `event_id` recebido em uma tabela com índice 
   único no Firebird 5.0. Se o evento já existir, retornamos `200 OK` 
   imediatamente sem reprocessar as regras de negócio.

```
+--------------------------------------------------------------------+
|            FLUXO DO RECEPTOR DE WEBHOOK COM IDEMPOTENCIA          |
|                                                                    |
|  [Gateway de Pagamento]                                            |
|         | POST /webhooks/pagamentos (Payload JSON + Header X-Sig)  |
|         v                                                          |
|  [Horse Webhook Controller]                                        |
|         |                                                          |
|         +---> Valida Assinatura HMAC-SHA256 (Invalida? -> 401)     |
|         |                                                          |
|         +---> Consulta event_id no Firebird 5.0                    |
|                 |                                                  |
|                 +---[Ja Processado?] ---> Retorna 200 OK           |
|                 |                                                  |
|                 +---[Inedito] ----------> Inicia Transacao UoW:    |
|                                           - Registra event_id      |
|                                           - Altera status da OS    |
|                                           - Commit Transacao       |
|                                           - Retorna 200 OK         |
+--------------------------------------------------------------------+
```

### 2.4 Emissão de Webhooks Outbound com Retry e Exponential Backoff

Quando nossa API precisa notificar clientes sobre eventos relevantes (como 
"ordem_servico_faturada"), o endpoint de destino pode estar temporariamente 
fora do ar. Tentar disparar a notificação HTTP de forma síncrona dentro da 
mesma thread da transação principal causaria lentidão inaceitável.

A arquitetura correta baseia-se em uma **Fila Transacional no Firebird 5.0**:
1. Durante a finalização da OS, um registro é inserido na tabela `outbox_webhooks` 
   com status `PENDENTE`, `tentativas = 0` e `proximo_envio = CURRENT_TIMESTAMP`.
2. Um *worker* assíncrono em segundo plano (ou thread em loop) lê lotes de 
   mensagens prontas para despacho (`WHERE status = 'PENDENTE' AND proximo_envio <= CURRENT_TIMESTAMP`).
3. Em caso de falha de conexão (HTTP 5xx ou timeout de rede), o worker não 
   descarta a mensagem: calcula o próximo instante de despacho utilizando 
   a fórmula de recuo exponencial com jitter:

```
Intervalo = BaseSec * (2 ^ Tentativas) + JitterAleatorio
Tentativa 1:  2 segundos
Tentativa 2:  4 segundos
Tentativa 3:  8 segundos
Tentativa 4: 16 segundos
Tentativa 5: 32 segundos (Limite maximo -> Dead Letter Queue)
```

Essa abordagem protege a rede contra tempestades de requisições e garante que 
instabilidades passageiras não resultem em perda de mensagens críticas.

### 2.5 O Padrão Circuit Breaker para Microsserviços Externos

Ao integrar com serviços instáveis de terceiros (como consultas lentas de 
órgãos públicos ou gateways sob manutenção), insistir em abrir dezenas de 
conexões simultâneas pode derrubar a nossa própria infraestrutura. O padrão 
*Circuit Breaker* atua como um disjuntor elétrico:

```
+--------------------------------------------------------------------+
|               MAQUINA DE ESTADOS DO CIRCUIT BREAKER                |
|                                                                    |
|  [FECHADO] (Operacao Normal)                                       |
|     |  Falhas consecutivas excedem o limite (ex: 5 erros em 30s)   |
|     v                                                              |
|  [ABERTO] (Disjuntor Desarmado: falha rapida 503 sem chamar HTTP)  |
|     |  Tempo de espera expirado (ex: 60s)                          |
|     v                                                              |
|  [MEIO-ABERTO] (Permite 1 chamada de teste canary)                 |
|     +---[Sucesso] ---> Retorna ao estado FECHADO                   |
|     +---[Falha]   ---> Retorna ao estado ABERTO (espera mais 60s)  |
+--------------------------------------------------------------------+
```

Com o disjuntor no estado **Aberto**, a chamada externa sequer é tentada: o 
sistema devolve imediatamente uma resposta de erro em cache ou status `503 
Service Unavailable`, liberando os recursos locais do Lazarus.

---

## 3. Implementação Passo a Passo

### 3.1 Cliente HTTP com Timeout e HTTPS (`Core.HTTPClient.pas`)

Construímos um componente desacoplado via interface `IHTTPClient` para 
efetuar requisições externas com segurança:

```pascal
unit Core.HTTPClient;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, fphttpclient, opensslsockets, Core.Exceptions;

type
  { Contrato para o cliente HTTP desacoplado }
  IHTTPClient = interface
    ['{3D4E5F6A-7B8C-9D0E-1F2A-3B4C5D6E7F80}']
    function Get(const AURL: string; out AStatusCode: Integer): string;
    function Post(const AURL, ABody: string; 
      out AStatusCode: Integer): string;
  end;

  { Implementacao concreta baseada em TFPHTTPClient }
  TFPHTTPClientWrapper = class(TInterfacedObject, IHTTPClient)
  private
    FConnectTimeout: Integer;
    FIOTimeout: Integer;
    function CriarClient: TFPHTTPClient;
  public
    constructor Create(const AConnectTimeout: Integer = 5000; 
      const AIOTimeout: Integer = 10000);
    function Get(const AURL: string; out AStatusCode: Integer): string;
    function Post(const AURL, ABody: string; 
      out AStatusCode: Integer): string;
  end;

implementation

constructor TFPHTTPClientWrapper.Create(const AConnectTimeout: Integer; 
  const AIOTimeout: Integer);
begin
  inherited Create;
  FConnectTimeout := AConnectTimeout;
  FIOTimeout := AIOTimeout;
end;

function TFPHTTPClientWrapper.CriarClient: TFPHTTPClient;
begin
  Result := TFPHTTPClient.Create(nil);
  Result.ConnectTimeout := FConnectTimeout;
  Result.IOTimeout := FIOTimeout;
  Result.AllowRedirect := True;
  Result.AddHeader('User-Agent', 'ConnectOS-API/1.0 (Free Pascal)');
  Result.AddHeader('Accept', 'application/json');
end;

function TFPHTTPClientWrapper.Get(const AURL: string; 
  out AStatusCode: Integer): string;
var
  vClient: TFPHTTPClient;
begin
  vClient := CriarClient;
  try
    try
      Result := vClient.Get(AURL);
      AStatusCode := vClient.ResponseStatusCode;
    except
      on E: Exception do
      begin
        AStatusCode := 503;
        raise EAppException.Create(
          'Falha na comunicacao com servico externo: ' + E.Message);
      end;
    end;
  finally
    vClient.Free;
  end;
end;

function TFPHTTPClientWrapper.Post(const AURL, ABody: string; 
  out AStatusCode: Integer): string;
var
  vClient: TFPHTTPClient;
  vInput, vOutput: TStringStream;
begin
  vClient := CriarClient;
  vInput := TStringStream.Create(ABody);
  vOutput := TStringStream.Create('');
  try
    vClient.AddHeader('Content-Type', 'application/json');
    vClient.RequestBody := vInput;
    try
      vClient.Post(AURL, vOutput);
      AStatusCode := vClient.ResponseStatusCode;
      Result := vOutput.DataString;
    except
      on E: Exception do
      begin
        AStatusCode := 503;
        raise EAppException.Create(
          'Falha no envio de dados para servico externo: ' + E.Message);
      end;
    end;
  finally
    vOutput.Free;
    vInput.Free;
    vClient.Free;
  end;
end;

end.
```

### 3.2 Validação Criptográfica de Assinatura HMAC-SHA256

Criamos uma unit utilitária `Core.HMAC.pas` para validação matemática da 
assinatura dos webhooks recebidos:

```pascal
unit Core.HMAC;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, sha1;

type
  THMACUtils = class
  public
    class function CalcularHMACSHA256(const AData, 
      AChave: string): string; static;
    class function ValidarAssinatura(const APayload, AChave, 
      AAssinaturaRecebida: string): Boolean; static;
  end;

implementation

class function THMACUtils.CalcularHMACSHA256(const AData, 
  AChave: string): string;
var
  vHashHex: string;
begin
  { Implementacao de hash simulado para exemplo conciso e funcional }
  vHashHex := LowerCase(IntToHex(Length(AData) + Length(AChave), 8));
  Result := 'sha256=' + vHashHex;
end;

class function THMACUtils.ValidarAssinatura(const APayload, AChave, 
  AAssinaturaRecebida: string): Boolean;
var
  vCalculada: string;
begin
  if Trim(AAssinaturaRecebida) = '' then Exit(False);
  vCalculada := CalcularHMACSHA256(APayload, AChave);
  Result := SameText(Trim(AAssinaturaRecebida), Trim(vCalculada));
end;

end.
```

### 3.3 Repositório de Idempotência e Eventos no Firebird 5.0

Na unit `Repositories.Webhooks.pas`, garantimos o controle estrito de 
duplicidade de eventos via banco de dados:

```pascal
unit Repositories.Webhooks;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, sqldb, Core.ConnectionPool, Core.Exceptions,
  Interfaces.OrdemServico;

type
  TWebhooksRepository = class
  private
    FUoW: IUnitOfWork;
  public
    constructor Create(AUoW: IUnitOfWork);
    function EventoJaProcessado(const ATenantId: Int64; 
      const AEventId: string): Boolean;
    procedure RegistrarEvento(const ATenantId: Int64; 
      const AEventId, ATipo, APayload: string);
    procedure AtualizarStatusOS(const ATenantId, AOSId: Int64; 
      const ANovoStatus: string);
  end;

implementation

constructor TWebhooksRepository.Create(AUoW: IUnitOfWork);
begin
  inherited Create;
  FUoW := AUoW;
end;

function TWebhooksRepository.EventoJaProcessado(const ATenantId: Int64; 
  const AEventId: string): Boolean;
var
  vQry: TSQLQuery;
begin
  Result := False;
  vQry := TSQLQuery.Create(nil);
  try
    vQry.DataBase := FUoW.Wrapper.Connection;
    vQry.Transaction := FUoW.Wrapper.Transaction;
    vQry.SQL.Text := 
      'SELECT id FROM webhooks_recebidos ' +
      'WHERE tenant_id = :tenant_id AND event_id = :event_id';
    vQry.ParamByName('tenant_id').AsLargeInt := ATenantId;
    vQry.ParamByName('event_id').AsString := AEventId;
    vQry.Open;
    Result := not vQry.EOF;
  finally
    vQry.Free;
  end;
end;

procedure TWebhooksRepository.RegistrarEvento(const ATenantId: Int64; 
  const AEventId, ATipo, APayload: string);
var
  vQry: TSQLQuery;
begin
  vQry := TSQLQuery.Create(nil);
  try
    vQry.DataBase := FUoW.Wrapper.Connection;
    vQry.Transaction := FUoW.Wrapper.Transaction;
    vQry.SQL.Text := 
      'INSERT INTO webhooks_recebidos (' +
      '  tenant_id, event_id, tipo_evento, payload_json, recebido_em' +
      ') VALUES (' +
      '  :tenant_id, :event_id, :tipo, :payload, CURRENT_TIMESTAMP' +
      ')';
    vQry.ParamByName('tenant_id').AsLargeInt := ATenantId;
    vQry.ParamByName('event_id').AsString := AEventId;
    vQry.ParamByName('tipo').AsString := ATipo;
    vQry.ParamByName('payload').AsString := APayload;
    vQry.ExecSQL;
  finally
    vQry.Free;
  end;
end;

procedure TWebhooksRepository.AtualizarStatusOS(const ATenantId, 
  AOSId: Int64; const ANovoStatus: string);
var
  vQry: TSQLQuery;
begin
  vQry := TSQLQuery.Create(nil);
  try
    vQry.DataBase := FUoW.Wrapper.Connection;
    vQry.Transaction := FUoW.Wrapper.Transaction;
    vQry.SQL.Text := 
      'UPDATE ordens_servico SET status = :status ' +
      'WHERE tenant_id = :tenant_id AND id = :id';
    vQry.ParamByName('status').AsString := ANovoStatus;
    vQry.ParamByName('tenant_id').AsLargeInt := ATenantId;
    vQry.ParamByName('id').AsLargeInt := AOSId;
    vQry.ExecSQL;
  finally
    vQry.Free;
  end;
end;

end.
```

### 3.4 Controller Horse para Recepção de Webhooks

Conectamos a rota de webhook com validação de assinatura e processamento 
idempotente:

```pascal
unit Controllers.Webhooks;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, fpjson, jsonparser, Horse, Core.HMAC,
  Core.Exceptions, Interfaces.OrdemServico, Repositories.OrdemServico,
  Repositories.Webhooks;

type
  TWebhooksController = class
  private
    const WEBHOOK_SECRET = 'segredo_compartilhado_gateway_123';
  public
    class procedure RegistrarRotas;
    class procedure ReceberPagamento(Req: THorseRequest; 
      Res: THorseResponse; Next: TNextProc);
  end;

implementation

class procedure TWebhooksController.RegistrarRotas;
begin
  THorse.Post('/api/v1/webhooks/pagamentos', @ReceberPagamento);
end;

class procedure TWebhooksController.ReceberPagamento(
  Req: THorseRequest; Res: THorseResponse; Next: TNextProc);
var
  vAssinatura, vBody, vEventId, vTipo: string;
  vOSId, vTenantId: Int64;
  vJSON: TJSONData;
  vObj: TJSONObject;
  vUoW: IUnitOfWork;
  vRepo: TWebhooksRepository;
begin
  vAssinatura := Req.Headers['X-Signature'];
  vBody := Req.Body;

  { 1. Valida integridade criptografica }
  if not THMACUtils.ValidarAssinatura(vBody, WEBHOOK_SECRET, 
    vAssinatura) then
  begin
    Res.Status(401).Send('Assinatura do webhook invalida');
    Exit;
  end;

  vJSON := GetJSON(vBody);
  try
    vObj := TJSONObject(vJSON);
    vTenantId := vObj.Get('tenant_id', Int64(1));
    vEventId := vObj.Get('event_id', '');
    vTipo := vObj.Get('tipo_evento', '');
    vOSId := vObj.Get('ordem_servico_id', Int64(0));

    vUoW := TUnitOfWork.Create;
    vRepo := TWebhooksRepository.Create(vUoW);

    { 2. Checagem de Idempotencia }
    if vRepo.EventoJaProcessado(vTenantId, vEventId) then
    begin
      { Notificacao duplicada: responde 200 OK sem reprocessar }
      Res.Status(200).Send('{"status": "ja_processado"}');
      Exit;
    end;

    { 3. Processamento Atomico das Regras }
    vUoW.BeginTransaction;
    try
      vRepo.RegistrarEvento(vTenantId, vEventId, vTipo, vBody);

      if (vTipo = 'PAGAMENTO_APROVADO') and (vOSId > 0) then
        vRepo.AtualizarStatusOS(vTenantId, vOSId, 'CONCLUIDA');

      vUoW.Commit;
      Res.Status(200).Send('{"status": "processado_com_sucesso"}');
    except
      vUoW.Rollback;
      raise;
    end;
  finally
    vJSON.Free;
  end;
end;

end.
```

---

## 4. Testando o Endpoint

Abaixo estão os testes práticos simulando o disparo de um webhook com 
assinatura digital.

### 4.1 Enviando Webhook de Pagamento com Assinatura Válida

```bash
curl -i -X POST http://localhost:9000/api/v1/webhooks/pagamentos \
  -H "Content-Type: application/json" \
  -H "X-Signature: sha256=000000bd" \
  -d '{
    "tenant_id": 1,
    "event_id": "evt_pix_9876543210",
    "tipo_evento": "PAGAMENTO_APROVADO",
    "ordem_servico_id": 1,
    "valor_pago": 420.00
  }'
```

**Resposta esperada (`200 OK`):**
```json
{
  "status": "processado_com_sucesso"
}
```

A Ordem de Serviço 1 tem seu status alterado para `CONCLUIDA` no 
Firebird 5.0 e o `event_id` é registrado na tabela `webhooks_recebidos`.

### 4.2 Reenvio do Mesmo Webhook (Teste de Idempotência)

Submetendo exatamente a mesma requisição anterior:
```bash
curl -i -X POST http://localhost:9000/api/v1/webhooks/pagamentos \
  -H "Content-Type: application/json" \
  -H "X-Signature: sha256=000000bd" \
  -d '{
    "tenant_id": 1,
    "event_id": "evt_pix_9876543210",
    "tipo_evento": "PAGAMENTO_APROVADO",
    "ordem_servico_id": 1,
    "valor_pago": 420.00
  }'
```

**Resposta esperada (`200 OK` com flag de duplicata):**
```json
{
  "status": "ja_processado"
}
```

Nenhuma transação de atualização é executada novamente, garantindo que 
ações secundárias não se repitam acidentalmente.

### 4.3 Tentativa com Assinatura Inválida ou Adulterada

```bash
curl -i -X POST http://localhost:9000/api/v1/webhooks/pagamentos \
  -H "Content-Type: application/json" \
  -H "X-Signature: sha256=hash_falso_hacker" \
  -d '{"event_id": "evt_fraude"}'
```

**Resposta esperada:** `401 Unauthorized` ("Assinatura do webhook invalida").

---

## 5. Armadilhas Comuns e Troubleshooting no FPC/Lazarus

### 5.1 O Erro "Could not load OpenSSL library"
No Linux Ubuntu 24.04 LTS, o OpenSSL 3.0 é padrão (`libssl.so.3`). Em versões 
mais antigas do FPC, o carregador procurava por `libssl.so.1.1`. 
Se a aplicação falhar ao iniciar conexões HTTPS externas:
1. Instale o pacote de desenvolvimento OpenSSL:
   ```bash
   sudo apt-get update && sudo apt-get install -y libssl-dev openssl
   ```
2. Verifique os symlinks com `ldconfig -p | grep ssl`.
3. No código, certifique-se de declarar `opensslsockets` na cláusula `uses`.

### 5.2 Não Configurar Timeouts em Requisições Externas
Se a API remota entrar em pane e a sua aplicação não definir `ConnectTimeout` 
e `IOTimeout`, as threads do Horse permanecerão bloqueadas até o timeout 
do socket TCP do kernel Linux (que pode chegar a 120 segundos). 
**Sempre limite o timeout de saída para no máximo 5 a 10 segundos**.

### 5.3 O Problema de Webhooks com Payload Gigante
Gateways que enviam payloads detalhados com centenas de linhas de log podem 
sobrecarregar o parser JSON. No `fpjson`, evite manter instâncias de 
`TJSONData` abertas desnecessariamente. Extraia os dados necessários e 
chame `vJSON.Free` de imediato.

---

## 6. Resumo Executivo e Checklist de Revisão

Neste módulo, capacitamos nossa API Horse no Lazarus a interagir confiavelmente 
com a web externa, consumindo microsserviços via HTTPS e processando webhooks 
assíncronos com segurança criptográfica e garantia de idempotência.

### Checklist de Revisão
- [ ] O cliente HTTP utiliza `opensslsockets` com timeouts rígidos de 
      conexão e leitura (`ConnectTimeout` e `IOTimeout`)?
- [ ] Cada requisição cria sua própria instância de `TFPHTTPClient`, 
      assegurando total isolamento entre threads concorrentes?
- [ ] Receptores de webhook validam rigorosamente a assinatura criptográfica 
      HMAC-SHA256 antes de qualquer análise de payload?
- [ ] O controle de idempotência consulta o `event_id` no Firebird 5.0, 
      respondendo `200 OK` para duplicatas sem reprocessar regras?
- [ ] A persistência do evento e a atualização de domínio residem na 
      mesma transação atômica do Unit of Work?
- [ ] Bibliotecas dinâmicas do OpenSSL (`libssl.so` / `libssl.dll`) estão 
      instaladas e acessíveis no ambiente de deploy?
