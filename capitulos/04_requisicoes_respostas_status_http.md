# MÓDULO 04: REQUISIÇÕES, RESPOSTAS, SEMÂNTICA DE CÓDIGOS HTTP E PADRÃO RFC 7807

---

## 1. OBJETIVOS DE APRENDIZAGEM DO MÓDULO

Ao final deste módulo, você será capaz de:

1. Dominar em profundidade os métodos, propriedades e o ciclo de vida dos objetos **`THorseRequest`** e **`THorseResponse`**.
2. Aplicar com rigor arquitetural a semântica dos códigos de status HTTP das famílias 2xx, 4xx e 5xx, eliminando o anti-padrão tóxico de "HTTP 200 com erro embutido".
3. Compreender a especificação internacional **RFC 7807 / RFC 9457 (Problem Details for HTTP APIs)**, identificando sua importância para a interoperabilidade entre backends Pascal e frontends modernos.
4. Construir uma unit reutilizável (`Core.ProblemDetails.pas`) em Object Pascal para geração padronizada de mensagens de erro estruturadas com cabeçalho `application/problem+json`.
5. Implementar respostas ricas com cabeçalhos de controle (`Location`, `Content-Type`, `Cache-Control`) e gerenciar fluxos sem corpo de mensagem (HTTP `204 No Content`).

---

## 2. FUNDAMENTAÇÃO CONCEITUAL E ARQUITETURAL

No Modelo de Maturidade de Richardson para serviços RESTful, o trânsito do Nível 1 (Recursos Individuais) para o Nível 2 (Verbos e Códigos HTTP) representa o divisor de águas entre sistemas artesanais e arquiteturas corporativas de classe mundial.

Historicamente, muitos desenvolvedores formados no modelo RPC (Remote Procedure Call) ou SOAP desenvolveram o vício prejudicial de responder invariavelmente com o código de status **`200 OK`**, encapsulando o sucesso ou a falha em um envelope JSON genérico:

```json
/* ANTI-PADRÃO TERRÍVEL: NUNCA ADOTE EM SUAS APIS */
HTTP/1.1 200 OK
Content-Type: application/json

{
  "sucesso": false,
  "mensagemErro": "Chave primária duplicada no Firebird",
  "codigo": 5001
}
```

Essa prática viola a essência do protocolo HTTP e introduz consequências graves:
- **Corrupção de Proxies e Balanceadores:** Servidores proxy reversos (como Nginx, HAProxy ou Cloudflare) e redes de distribuição de conteúdo (CDNs) interpretam o código 200 como um documento válido e podem armazenar a resposta de erro em cache, servindo-a para centenas de outros clientes.
- **Falha em Políticas de Retry Automático:** Bibliotecas de clientes HTTP (como Axios no frontend ou Polly em microsserviços) dependem do código HTTP para disparar retentativas automáticas e chaveamento de circuitos (*circuit breakers*) diante de erros transientes (ex: 503 ou 429). Responder 200 sabota essa inteligência.
- **Acoplamento Desnecessário:** O cliente é forçado a realizar o parsing manual de todo o corpo JSON apenas para saber se a requisição foi aceita ou rejeitada.

```
+-------------------------------------------------------------------+
|               HIERARQUIA SEMÂNTICA DOS STATUS HTTP                |
+-------------------------------------------------------------------+
|                                                                   |
| [ 2xx - SUCESSO ]                                                 |
|  - 200 OK           : Requisição atendida com payload de retorno. |
|  - 201 Created      : Novo recurso criado (exige header Location).|
|  - 204 No Content   : Sucesso absoluto; proibido retornar corpo.  |
|                                                                   |
| [ 4xx - ERRO DO CLIENTE ]                                         |
|  - 400 Bad Request  : Sintaxe malformada ou parâmetros inválidos. |
|  - 401 Unauthorized : Ausência ou invalidade de token/credencial. |
|  - 403 Forbidden    : Identidade conhecida, mas sem permissão.    |
|  - 404 Not Found    : O recurso solicitado não existe na URI.     |
|  - 409 Conflict     : Violação de regra de unicidade ou estado.   |
|  - 422 Unprocessable: Sintaxe JSON correta, mas semântica falha.  |
|                                                                   |
| [ 5xx - ERRO DO SERVIDOR ]                                        |
|  - 500 Internal Err : Falha inesperada de infraestrutura/código.  |
|  - 503 Unavailable  : Sobrecarga temporária ou manutenção ativa.  |
+-------------------------------------------------------------------+
```

### A Especificação RFC 7807 (Problem Details for HTTP APIs)

Quando uma requisição falha (status 4xx ou 5xx), o cliente precisa entender exatamente **o que** deu errado, **por que** ocorreu o erro e **como** corrigi-lo. A IETF padronizou esse mecanismo através da **RFC 7807** (recentemente atualizada pela RFC 9457), definindo um formato de documento JSON padronizado com o MIME type específico:

```http
Content-Type: application/problem+json
```

O esquema de um documento de detalhamento de problemas compõe-se de cinco propriedades canônicas fundamentais:

1. **`type` (string URI):** Um identificador URI absoluto ou relativo que aponta para a documentação técnica daquele tipo específico de erro (ex: `https://api.connectos.com/erros/cliente-duplicado`).
2. **`title` (string):** Um resumo curto, direto e legível por humanos sobre a categoria do problema (ex: `Conflito de Identificação`). Não deve mudar entre diferentes ocorrências do mesmo tipo de erro.
3. **`status` (integer):** O código de status HTTP numérico gerado pelo servidor para esta ocorrência (ex: `409`).
4. **`detail` (string):** Uma explicação detalhada, específica e contextual desta ocorrência particular do erro (ex: `O CNPJ 12.345.678/0001-99 já está vinculado a outro cadastro ativo`).
5. **`instance` (string URI):** Uma URI ou identificador de rastreabilidade único que referencia esta ocorrência específica (ex: `/api/v1/erros/req-8a4b-991c`). Excelente para correlacionar chamadas com logs no `journalctl`.
6. **Membros de Extensão (*Extension Members*):** A especificação permite expressamente estender o JSON com propriedades customizadas, como a lista de campos que falharam na validação (`invalidParams`).

> **Nota de Arquitetura:**  
> A separação formal entre `title` e `detail` é primordial: `title` expressa o conceito genérico do erro (estático), enquanto `detail` fornece o diagnóstico pontual da requisição falha (dinâmico). Isso permite que clientes internacionais utilizem o `type` ou `title` para internacionalização (i18n) na interface gráfica sem acoplamento com a mensagem em português vinda do backend.

---

## 3. IMPLEMENTAÇÃO PASSO A PASSO

Implementaremos agora o motor de tratamento padronizado de respostas e erros para o projeto **ConnectOSApi**. Criaremos a unit central de domínio `Core.ProblemDetails.pas` e atualizaremos nossos controladores para utilizá-la nativamente.

### Passo 1: Construindo a Unit Core.ProblemDetails.pas

A unit abaixo encapsula a estrutura da RFC 7807 em um record moderno com métodos de construção fluente (*fluent builder*) e formatação JSON limpa, sem dependências de bibliotecas de terceiros:

```pascal
{======================================================================}
{ Projeto: ConnectOSApi - API de Gestao e Faturamento Multi-Tenant     }
{ Unit   : Core.ProblemDetails                                         }
{ Papel  : Formatador e serializador RFC 7807 (Problem Details)        }
{======================================================================}
unit Core.ProblemDetails;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  Horse;

type
  { Registro para detalhamento de erros de validacao por campo }
  TInvalidParam = record
    Campo: string;
    Motivo: string;
  end;

  { Estrutura de dados canônica da RFC 7807 / RFC 9457 }
  TProblemDetails = record
  private
    FType: string;
    FTitle: string;
    FStatus: Integer;
    FDetail: string;
    FInstance: string;
    FInvalidParams: array of TInvalidParam;
  public
    class function CreateNew: TProblemDetails; static;
    function SetType(const AType: string): TProblemDetails;
    function SetTitle(const ATitle: string): TProblemDetails;
    function SetStatus(const AStatus: Integer): TProblemDetails;
    function SetDetail(const ADetail: string): TProblemDetails;
    function SetInstance(const AInstance: string): TProblemDetails;
    function AddInvalidParam(const ACampo, AMotivo: string): 
      TProblemDetails;
    function ToJSON: string;
    procedure SendTo(Res: THorseResponse);
  end;

implementation

{ TProblemDetails }

class function TProblemDetails.CreateNew: TProblemDetails;
begin
  Result.FType := 'about:blank';
  Result.FTitle := 'Erro Inesperado';
  Result.FStatus := 500;
  Result.FDetail := '';
  Result.FInstance := '';
  SetLength(Result.FInvalidParams, 0);
end;

function TProblemDetails.SetType(const AType: string): TProblemDetails;
begin
  FType := AType;
  Result := Self;
end;

function TProblemDetails.SetTitle(const ATitle: string): 
  TProblemDetails;
begin
  FTitle := ATitle;
  Result := Self;
end;

function TProblemDetails.SetStatus(const AStatus: Integer): 
  TProblemDetails;
begin
  FStatus := AStatus;
  Result := Self;
end;

function TProblemDetails.SetDetail(const ADetail: string): 
  TProblemDetails;
begin
  FDetail := ADetail;
  Result := Self;
end;

function TProblemDetails.SetInstance(const AInstance: string): 
  TProblemDetails;
begin
  FInstance := AInstance;
  Result := Self;
end;

function TProblemDetails.AddInvalidParam(
  const ACampo, AMotivo: string): TProblemDetails;
var
  vLen: Integer;
begin
  vLen := Length(FInvalidParams);
  SetLength(FInvalidParams, vLen + 1);
  FInvalidParams[vLen].Campo := ACampo;
  FInvalidParams[vLen].Motivo := AMotivo;
  Result := Self;
end;

function TProblemDetails.ToJSON: string;
var
  vJSON: string;
  i: Integer;
begin
  vJSON := '{' +
           '"type":"' + FType + '",' +
           '"title":"' + FTitle + '",' +
           '"status":' + IntToStr(FStatus) + ',' +
           '"detail":"' + FDetail + '"';

  if FInstance <> '' then
    vJSON := vJSON + ',"instance":"' + FInstance + '"';

  { Serializacao dos parametros invalidos caso existam }
  if Length(FInvalidParams) > 0 then
  begin
    vJSON := vJSON + ',"invalidParams":[';
    for i := 0 to High(FInvalidParams) do
    begin
      if i > 0 then
        vJSON := vJSON + ',';
      vJSON := vJSON + '{"campo":"' + FInvalidParams[i].Campo + '",' +
                       '"motivo":"' + FInvalidParams[i].Motivo + '"}';
    end;
    vJSON := vJSON + ']';
  end;

  vJSON := vJSON + '}';
  Result := vJSON;
end;

procedure TProblemDetails.SendTo(Res: THorseResponse);
begin
  { Define o MIME type canonico RFC 7807 }
  Res.RawWebResponse.ContentType := 'application/problem+json; ' +
                                    'charset=utf-8';
  Res.Send(ToJSON)
     .Status(THTTPStatus(FStatus));
end;

end.
```

> **Boas Práticas FPC:**  
> A utilização de `record` em substituição a `class` para DTOs transitórios como o `TProblemDetails` confere um ganho substancial de desempenho e segurança no Free Pascal. Os registros (*records*) são alocados diretamente na pilha (*stack*) da thread corrente e destruídos automaticamente assim que saem de escopo ao término do procedimento da rota. Isso elimina completamente a necessidade de blocos `try..finally` com chamadas a `.Free`, neutralizando 100% dos riscos de vazamento de memória sob tráfego volumoso.

---

### Passo 2: Refatorando o Controlador de Clientes com RFC 7807

Vamos atualizar o arquivo `src/Controllers/Controllers.Clientes.pas` para que todas as rejeições de entrada (400, 404, 409, 422) adotem formalmente o padrão RFC 7807 utilizando nossa nova unit:

```pascal
unit Controllers.Clientes;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  Horse,
  Core.ProblemDetails;

type
  TControllersClientes = class
  private
    class procedure Listar(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
    class procedure ObterPorId(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
    class procedure Criar(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
    class procedure Excluir(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
  public
    class procedure Registry;
  end;

implementation

{ TControllersClientes }

class procedure TControllersClientes.Listar(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vTenantId: string;
begin
  vTenantId := Req.Headers.Field('X-Tenant-ID').AsString;
  if Trim(vTenantId) = '' then
  begin
    TProblemDetails.CreateNew
      .SetType('https://api.connectos.com/erros/tenant-obrigatorio')
      .SetTitle('Cabecalho de Inquilino Ausente')
      .SetStatus(400)
      .SetDetail('O cabecalho X-Tenant-ID e mandatorio para listar.')
      .SetInstance(Req.RawWebRequest.PathInfo)
      .SendTo(Res);
    Exit;
  end;

  Res.Send('{"meta":{"total":1},"dados":[{"id":101,"nome":"Acme"}]}')
     .Status(THTTPStatus.OK);
end;

class procedure TControllersClientes.ObterPorId(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vClienteId: Int64;
begin
  vClienteId := StrToInt64Def(Req.Params.Field('id').AsString, 0);

  if vClienteId <= 0 then
  begin
    TProblemDetails.CreateNew
      .SetType('https://api.connectos.com/erros/parametro-invalido')
      .SetTitle('Parametro de Rota Invalido')
      .SetStatus(400)
      .SetDetail('O identificador de cliente na URI deve ser numerico.')
      .SetInstance(Req.RawWebRequest.PathInfo)
      .SendTo(Res);
    Exit;
  end;

  if vClienteId = 404 then
  begin
    TProblemDetails.CreateNew
      .SetType('https://api.connectos.com/erros/recurso-inexistente')
      .SetTitle('Cliente Nao Localizado')
      .SetStatus(404)
      .SetDetail('Nenhum cliente ativo localizado com o ID ' + 
                 IntToStr(vClienteId) + '.')
      .SetInstance(Req.RawWebRequest.PathInfo)
      .SendTo(Res);
    Exit;
  end;

  Res.Send('{"id":' + IntToStr(vClienteId) + ',"nome":"Acme Ind"}')
     .Status(THTTPStatus.OK);
end;

class procedure TControllersClientes.Criar(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vBody: string;
  vProblem: TProblemDetails;
begin
  vBody := Trim(Req.Body);

  { Simulacao de validacao de campos de formulario (422) }
  if vBody = '' then
  begin
    vProblem := TProblemDetails.CreateNew
      .SetType('https://api.connectos.com/erros/entidade-improcessavel')
      .SetTitle('Falha de Validacao de Dados')
      .SetStatus(422)
      .SetDetail('O corpo da requisicao contem campos invalidos.')
      .SetInstance(Req.RawWebRequest.PathInfo)
      .AddInvalidParam('nome_razao', 
        'O campo razao social e obrigatorio')
      .AddInvalidParam('cpf_cnpj', 'O documento informado e invalido');

    vProblem.SendTo(Res);
    Exit;
  end;

  { Simulacao de conflito de chave duplicada (409) }
  if Pos('11111111000199', vBody) > 0 then
  begin
    TProblemDetails.CreateNew
      .SetType('https://api.connectos.com/erros/conflito-documento')
      .SetTitle('Conflito de Identificacao')
      .SetStatus(409)
      .SetDetail('Ja existe um cliente ativo com o CNPJ informado.')
      .SetInstance(Req.RawWebRequest.PathInfo)
      .SendTo(Res);
    Exit;
  end;

  Res.RawWebResponse.SetCustomHeader('Location', 
    '/api/v1/clientes/301');
  Res.Send('{"id":301,"mensagem":"Criado com sucesso"}')
     .Status(THTTPStatus.Created);
end;

class procedure TControllersClientes.Excluir(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vClienteId: Int64;
begin
  vClienteId := StrToInt64Def(Req.Params.Field('id').AsString, 0);
  if vClienteId <= 0 then
  begin
    TProblemDetails.CreateNew
      .SetType('https://api.connectos.com/erros/parametro-invalido')
      .SetTitle('Parametro Invalido para Exclusao')
      .SetStatus(400)
      .SetDetail('Identificador numerico esperado.')
      .SendTo(Res);
    Exit;
  end;

  { 204 No Content absoluto, sem corpo }
  Res.Status(THTTPStatus.NoContent);
end;

class procedure TControllersClientes.Registry;
begin
  THorse.Get('/api/v1/clientes', @Listar);
  THorse.Get('/api/v1/clientes/:id', @ObterPorId);
  THorse.Post('/api/v1/clientes', @Criar);
  THorse.Delete('/api/v1/clientes/:id', @Excluir);
end;

end.
```

---

## 4. TESTANDO O ENDPOINT

Vamos validar experimentalmente como as respostas de erro estruturadas da RFC 7807 se comportam na prática através de cenários de teste automatizados com `curl`.

### Teste 1: Rejeição Semântica com Campos Inválidos (422 Unprocessable Entity)

Envie uma requisição `POST` com o corpo deliberadamente em branco:

```bash
curl -i -X POST http://localhost:9000/api/v1/clientes \
     -H "Content-Type: application/json" \
     -d ""
```

**Resposta Padronizada da RFC 7807 Retornada:**

```http
HTTP/1.1 422 Unprocessable Entity
Content-Type: application/problem+json; charset=utf-8
Content-Length: 326
Date: Mon, 23 Nov 2026 11:55:00 GMT
Server: fphttpserver

{"type":"https://api.connectos.com/erros/entidade-improcessavel",
 "title":"Falha de Validacao de Dados",
 "status":422,
 "detail":"O corpo da requisicao contem campos invalidos.",
 "instance":"/api/v1/clientes",
 "invalidParams":[
   {"campo":"nome_razao","motivo":"O campo razao social e obrigatorio"},
   {"campo":"cpf_cnpj","motivo":"O documento informado e invalido"}
 ]}
```

Observe que qualquer cliente de frontend pode consumir imediatamente a lista `invalidParams` e destacar visualmente os campos com borda vermelha e suas respectivas mensagens de erro na interface do usuário, sem qualquer ambiguidade.

---

### Teste 2: Conflito de Integridade de Dados (409 Conflict)

Envie uma requisição com um CNPJ já cadastrado:

```bash
curl -i -X POST http://localhost:9000/api/v1/clientes \
     -H "Content-Type: application/json" \
     -d '{"cpf_cnpj":"11111111000199"}'
```

**Resposta do Servidor (409 Conflict):**

```http
HTTP/1.1 409 Conflict
Content-Type: application/problem+json; charset=utf-8
Content-Length: 238

{"type":"https://api.connectos.com/erros/conflito-documento",
 "title":"Conflito de Identificacao",
 "status":409,
 "detail":"Ja existe um cliente ativo com o CNPJ informado.",
 "instance":"/api/v1/clientes"}
```

---

### Teste 3: Recurso Não Localizado (404 Not Found)

Consulte o cliente com ID inexistente `404`:

```bash
curl -i http://localhost:9000/api/v1/clientes/404
```

**Resposta do Servidor (404 Not Found):**

```http
HTTP/1.1 404 Not Found
Content-Type: application/problem+json; charset=utf-8
Content-Length: 226

{"type":"https://api.connectos.com/erros/recurso-inexistente",
 "title":"Cliente Nao Localizado",
 "status":404,
 "detail":"Nenhum cliente ativo localizado com o ID 404.",
 "instance":"/api/v1/clientes/404"}
```

---

## 5. ARMADILHAS COMUNS E TROUBLESHOOTING NO FPC/LAZARUS

---

### Armadilha 1: Retornar Corpo de Conteúdo em Respostas 204 No Content

**Sintoma:** Ao chamar o endpoint de exclusão (`DELETE`), navegadores ou clientes HTTP estritos travam a conexão ou emitem avisos de violação de protocolo:

```text
ProtocolViolation: Response with status 204
MUST NOT include a message-body.
```

**Causa Raiz:** O desenvolvedor executa `Res.Send('{"msg":"Excluido"}').Status(204);`.

**Solução:** Quando o status for 204, **nunca** invoque o método `Send`. Apenas atribua o status:

```pascal
{ CORRETO }
Res.Status(THTTPStatus.NoContent);
```

---

### Armadilha 2: Omitir o MIME Type application/problem+json

**Sintoma:** Ferramentas de auditoria de API e clientes modernos tratam o erro como texto simples e recusam o parsing do JSON.

**Causa Raiz:** Deixar o cabeçalho `Content-Type` padrão (`text/plain`).

**Solução:** Conforme demonstrado no método `TProblemDetails.SendTo`, sempre defina:

```pascal
Res.RawWebResponse.ContentType := 
  'application/problem+json; charset=utf-8';
```

---

### Armadilha 3: Vazamento de Stack Traces e Detalhes de Banco em Produção

**Sintoma:** Ao ocorrer um erro 500 decorrente de uma falha de SQL no Firebird, o campo `detail` do JSON expõe a instrução SQL completa, nomes de tabelas internas e o endereço de memória do servidor.

**Causa Raiz:** Capturar a exceção com `except on E: Exception do` e repassar `E.Message` diretamente para o cliente externo.

**Solução:** Em ambiente de produção, mascare detalhes internos. Logue a mensagem técnica no terminal/journalctl e retorne ao cliente apenas um código genérico rastreável via `instance` (Correlation-ID).

---

## 6. RESUMO EXECUTIVO E CHECKLIST DE REVISÃO

### Tabela de Mapeamento RFC 7807 para APIs Lazarus

| Código HTTP | Título RFC 7807 Sugerido | Cenário de Aplicação Típico |
| :--- | :--- | :--- |
| **`400`** | `Parametro Invalido` | Sintaxe JSON corrompida ou tipo de dado incorreto. |
| **`401`** | `Nao Autenticado` | Token JWT ausente, expirado ou com assinatura inválida.|
| **`403`** | `Acesso Negado` | Usuário autenticado tentando acessar outro Tenant. |
| **`404`** | `Recurso Inexistente` | Registro de ID solicitado não consta no Firebird. |
| **`409`** | `Conflito de Estado` | CNPJ/CPF já existente ou chave única violada. |
| **`422`** | `Entidade Improcessavel` | Regras de validação de negócio reprovadas (ex: CEP). |
| **`500`** | `Erro Interno de Servidor` | Exceção não tratada capturada pelo pipeline global. |

---

### Checklist de Revisão e Auditoria Técnica

Antes de dar por encerrado o **Bloco I**, certifique-se de validar os seguintes itens fundamentais:

- [ ] **Abolição do Anti-padrão:** A API não responde status 200 para operações que resultaram em erro.
- [ ] **MIME Type RFC 7807:** Todas as respostas 4xx e 5xx configuram o cabeçalho `Content-Type: application/problem+json; charset=utf-8`.
- [ ] **Estrutura Problem Details:** O JSON de erro contém ao menos as propriedades canônicas `type`, `title`, `status`, `detail` e `instance`.
- [ ] **Detalhamento de Validação:** Em respostas 422, a propriedade `invalidParams` detalha os campos que falharam e seus motivos.
- [ ] **Respeito Absoluto ao 204:** Operações de exclusão não enviam nenhum byte no corpo da mensagem.
- [ ] **Cabeçalho Location no 201:** Operações de cadastro bem-sucedidas emitem o cabeçalho `Location` com a rota de consulta do novo recurso.

Com a conclusão do Módulo 04, finalizamos com sucesso absoluto o **BLOCO I — FUNDAMENTOS DO HORSE E SERVIDORES NATIVOS EM LAZARUS**. Estamos agora prontos para avançar para o **BLOCO II**, onde construiremos o pipeline de middlewares avançados, decodificação JSON com `fpjson` e `Jhonson`, tratamento global de exceções e segurança stateless com JWT.
