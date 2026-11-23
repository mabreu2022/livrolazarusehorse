# MÓDULO 03: ROTEAMENTO AVANÇADO, VERBOS HTTP E PARÂMETROS

---

## 1. OBJETIVOS DE APRENDIZAGEM DO MÓDULO

Ao final deste módulo, você será capaz de:

1. Compreender o mecanismo interno de indexação e casamento de rotas do **Horse**, identificando como o despachante localiza handlers a partir do método HTTP e da URI requisitada.
2. Aplicar a semântica estrita dos verbos HTTP fundamentais do padrão RESTful: `GET`, `POST`, `PUT`, `PATCH` e `DELETE`.
3. Manipular com precisão e segurança os três tipos de parâmetros de entrada: parâmetros de rota na URI (`Req.Params`), parâmetros de consulta (*query string* via `Req.Query`) e cabeçalhos de contexto (*headers* via `Req.Headers`).
4. Estruturar agrupamentos modulares de rotas utilizando `THorse.Group` e prefixos lógicos para implementar estratégias limpas de versionamento de API (`/api/v1` e `/api/v2`).
5. Prevenir armadilhas críticas de colisão de rotas (*shadowing* de rotas estáticas versus dinâmicas) e evitar exceções de conversão de tipos em ambientes multithread.

---

## 2. FUNDAMENTAÇÃO CONCEITUAL E ARQUITETURAL

O coração de qualquer framework web moderno repousa sobre o seu mecanismo de roteamento (*router engine*). Em arquiteturas de microsserviços e APIs corporativas, o roteador é submetido a milhares de chamadas por segundo e precisa inspecionar cada pacote recebido, extrair variáveis dinâmicas e encaminhar o fluxo de execução para a função manipuladora correta no menor tempo de CPU possível.

No Horse, a tabela de rotas é mantida em memória como uma estrutura hierárquica indexada primariamente pelo verbo HTTP e segmentada pelos nós da URI.

```
                   +--------------------------------+
                   |  REQUISIÇÃO ENTRANTE NO HORSE  |
                   |  POST /api/v1/clientes/42/foto |
                   +--------------------------------+
                                   |
                                   v
             [ Seleciona Tabela de Roteamento por Verbo ]
                                   |
             +---------------------+---------------------+
             |         |           |           |         |
            GET       POST        PUT        PATCH     DELETE
                       |
                       v
             [ Árvore de Segmentos de Caminho (Trie/Prefix) ]
                       |
                       +---> /api
                               |
                               +---> /v1
                                       |
                                       +---> /clientes
                                               |
                                               +---> /:id (Captura "42")
                                                       |
                                                       +---> /foto
                                                               |
                                                               v
                                                    [ Executa Handler ]
```

### Semântica Rigorosa dos Verbos HTTP no Modelo REST

Um dos erros conceituais mais danosos na engenharia de APIs é desrespeitar as propriedades de **segurança (*safety*)** e **idempotência (*idempotency*)** estabelecidas pela especificação RFC 9110 (HTTP Semantics). Compreender essas propriedades é pré-requisito mandatório para projetar sistemas confiáveis:

| Verbo HTTP | Seguro? (Não altera estado) | Idempotente? (N repetições = 1 efeito) | Finalidade Arquitetural Típica |
| :--- | :--- | :--- | :--- |
| **`GET`** | **Sim** | **Sim** | Recuperação de recursos sem efeitos colaterais. |
| **`POST`** | Não | Não | Criação de novos recursos ou comandos operacionais. |
| **`PUT`** | Não | **Sim** | Substituição integral de um recurso existente. |
| **`PATCH`** | Não | Não (Geralmente Sim) | Atualização cirúrgica/parcial de campos. |
| **`DELETE`**| Não | **Sim** | Exclusão lógica ou física do recurso. |

> **Nota de Arquitetura:**  
> Um método é considerado **seguro** quando sua invocação não produz nenhuma alteração no estado observável dos recursos do servidor (operações puras de leitura). Um método é considerado **idempotente** quando o efeito colateral de realizar uma única requisição com sucesso é rigorosamente idêntico ao efeito de realizar $N$ requisições idênticas consecutivas. Se uma chamada de rede falhar no meio do caminho e o cliente reenviar um `PUT` ou `DELETE`, o estado final do sistema deve ser o mesmo. Já o `POST` não é idempotente: reexecutá-lo cria registros duplicados a menos que se use chaves de idempotência.

### Anatomia dos Três Tipos de Parâmetros HTTP

Ao projetar uma API em Horse, o desenvolvedor deve selecionar conscientemente o mecanismo adequado para transportar dados do cliente para a aplicação:

1. **Parâmetros de Rota (`Req.Params`):**
   - **Localização:** Incrustados no próprio caminho da URL (ex: `/clientes/:id/enderecos/:seq`).
   - **Propósito:** Identificação única de recursos hierárquicos e relacionamentos essenciais.
   - **Sintaxe no Horse:** Prefixados por dois pontos (`:nome_parametro`).
2. **Parâmetros de Consulta / Query String (`Req.Query`):**
   - **Localização:** Após o caractere `?` na URL (ex: `/clientes?ativo=true&pagina=2&limite=20`).
   - **Propósito:** Filtros, paginação, ordenação e opções de projeção que não alteram a identidade ontológica do recurso.
   - **Sintaxe no Horse:** Extraídos através da coleção `Req.Query`.
3. **Cabeçalhos de Requisição (`Req.Headers`):**
   - **Localização:** Metadados transmitidos no cabeçalho HTTP (ex: `X-Tenant-ID: 1`, `Authorization: Bearer <token>`).
   - **Propósito:** Informações de infraestrutura, controle de segurança, rastreabilidade distribuída (*tracing*) e contexto de inquilino (*tenant*).

### Versionamento e Agrupamento de Rotas com THorse.Group

Em ecossistemas corporativos que atendem a múltiplos clientes (aplicativos móveis, portais web e sistemas legados de terceiros), contratos de API evoluem ao longo do tempo. Alterações de quebra (*breaking changes*) não podem ser publicadas diretamente sobre rotas existentes sob o risco de paralisar clientes desatualizados.

O Horse disponibiliza a classe utilitária de agrupamento e a técnica de prefixação, permitindo agrupar famílias de rotas sob prefixos comuns, tais como `/api/v1` e `/api/v2`:

```pascal
{ Agrupamento semantico de rotas }
THorse.Group
  .Prefix('/api/v1')
  .Get('/clientes', @ListarClientesV1)
  .Post('/clientes', @CriarClienteV1);

THorse.Group
  .Prefix('/api/v2')
  .Get('/clientes', @ListarClientesV2);
```

Essa abordagem garante que novos campos, regras de validação ou reformulações de DTO possam coexistir pacificamente com versões estáveis anteriores.

---

## 3. IMPLEMENTAÇÃO PASSO A PASSO

Construiremos agora um controlador completo para o gerenciamento de **Clientes** do nosso projeto prático **ConnectOSApi**. Este controlador implementará todas as operações CRUD fundamentais utilizando os verbos HTTP correspondentes, ilustrando a leitura segura de parâmetros de rota, query string, cabeçalhos de inquilino (*tenant*) e corpo da requisição.

### Criando a Unit de Controlador: Controllers.Clientes.pas

Crie o arquivo `src/Controllers/Controllers.Clientes.pas` respeitando rigorosamente o limite de 72 caracteres por linha:

```pascal
{======================================================================}
{ Projeto: ConnectOSApi - API de Gestao e Faturamento Multi-Tenant     }
{ Unit   : Controllers.Clientes                                        }
{ Papel  : Controlador RESTful completo para o recurso Clientes        }
{======================================================================}
unit Controllers.Clientes;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  Horse;

type
  { Controlador RESTful para Gestao de Clientes }
  TControllersClientes = class
  private
    class procedure Listar(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
    class procedure ObterPorId(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
    class procedure Criar(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
    class procedure AtualizarIntegral(Req: THorseRequest; 
      Res: THorseResponse; Next: TNextProc);
    class procedure AtualizarStatus(Req: THorseRequest; 
      Res: THorseResponse; Next: TNextProc);
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
  vPagina: Integer;
  vLimite: Integer;
  vTermoBusca: string;
  vResposta: string;
begin
  { 1. Captura obrigatoria do identificador do Tenant via Header }
  vTenantId := Req.Headers.Field('X-Tenant-ID').AsString;
  if Trim(vTenantId) = '' then
  begin
    Res.Send('{"erro":"Cabecalho X-Tenant-ID e obrigatorio"}')
       .Status(THTTPStatus.BadRequest);
    Exit;
  end;

  { 2. Captura de parametros opcionais de paginacao na Query String }
  vPagina := StrToIntDef(Req.Query.Field('pagina').AsString, 1);
  vLimite := StrToIntDef(Req.Query.Field('limite').AsString, 10);
  vTermoBusca := Req.Query.Field('busca').AsString;

  { Simulacao de envelope de resposta paginada }
  vResposta := '{"meta":{"tenant":"' + vTenantId + '",' +
               '"pagina":' + IntToStr(vPagina) + ',' +
               '"limite":' + IntToStr(vLimite) + ',' +
               '"filtro":"' + vTermoBusca + '",' +
               '"total":1},' +
               '"dados":[{"id":101,"nome_razao":"Acme Indústria",' +
               '"cpf_cnpj":"12345678000199","ativo":true}]}';

  Res.Send(vResposta)
     .Status(THTTPStatus.OK);
end;

class procedure TControllersClientes.ObterPorId(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vIdParam: string;
  vClienteId: Int64;
  vResposta: string;
begin
  { Captura do parametro de rota :id }
  vIdParam := Req.Params.Field('id').AsString;
  vClienteId := StrToInt64Def(vIdParam, 0);

  if vClienteId <= 0 then
  begin
    Res.Send('{"erro":"Identificador de cliente invalido na URI"}')
       .Status(THTTPStatus.BadRequest);
    Exit;
  end;

  { Simulacao de busca por identificador }
  if vClienteId = 404 then
  begin
    Res.Send('{"erro":"Cliente nao localizado"}')
       .Status(THTTPStatus.NotFound);
    Exit;
  end;

  vResposta := '{"id":' + IntToStr(vClienteId) + ',' +
               '"nome_razao":"Auto Mecanica Central LTDA",' +
               '"cpf_cnpj":"98765432000188",' +
               '"email":"contato@automecanica.com.br",' +
               '"ativo":true}';

  Res.Send(vResposta)
     .Status(THTTPStatus.OK);
end;

class procedure TControllersClientes.Criar(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vBody: string;
  vNovoId: Int64;
  vResposta: string;
begin
  { Leitura do payload bruto recebido no corpo da requisicao }
  vBody := Req.Body;
  if Trim(vBody) = '' then
  begin
    Res.Send('{"erro":"Corpo da requisicao (payload) nao informado"}')
       .Status(THTTPStatus.UnprocessableEntity);
    Exit;
  end;

  { Simulacao de persistencia e geracao de ID no Firebird }
  vNovoId := 205;

  vResposta := '{"mensagem":"Cliente cadastrado com sucesso",' +
               '"id":' + IntToStr(vNovoId) + '}';

  { 201 Created com cabecalho Location indicando o novo recurso }
  Res.RawWebResponse.SetCustomHeader('Location', 
    '/api/v1/clientes/' + IntToStr(vNovoId));

  Res.Send(vResposta)
     .Status(THTTPStatus.Created);
end;

class procedure TControllersClientes.AtualizarIntegral(
  Req: THorseRequest; Res: THorseResponse; Next: TNextProc);
var
  vClienteId: Int64;
  vBody: string;
  vResposta: string;
begin
  vClienteId := StrToInt64Def(Req.Params.Field('id').AsString, 0);
  if vClienteId <= 0 then
  begin
    Res.Send('{"erro":"Identificador invalido para substituicao"}')
       .Status(THTTPStatus.BadRequest);
    Exit;
  end;

  vBody := Req.Body;
  if Trim(vBody) = '' then
  begin
    Res.Send('{"erro":"Dados para substituicao integral ausentes"}')
       .Status(THTTPStatus.UnprocessableEntity);
    Exit;
  end;

  vResposta := '{"mensagem":"Cliente substituido integralmente",' +
               '"id":' + IntToStr(vClienteId) + '}';

  Res.Send(vResposta)
     .Status(THTTPStatus.OK);
end;

class procedure TControllersClientes.AtualizarStatus(
  Req: THorseRequest; Res: THorseResponse; Next: TNextProc);
var
  vClienteId: Int64;
  vBody: string;
  vResposta: string;
begin
  vClienteId := StrToInt64Def(Req.Params.Field('id').AsString, 0);
  if vClienteId <= 0 then
  begin
    Res.Send('{"erro":"Identificador de cliente invalido"}')
       .Status(THTTPStatus.BadRequest);
    Exit;
  end;

  vBody := Req.Body;

  vResposta := '{"mensagem":"Status do cliente alterado via PATCH",' +
               '"id":' + IntToStr(vClienteId) + '}';

  Res.Send(vResposta)
     .Status(THTTPStatus.OK);
end;

class procedure TControllersClientes.Excluir(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vClienteId: Int64;
begin
  vClienteId := StrToInt64Def(Req.Params.Field('id').AsString, 0);
  if vClienteId <= 0 then
  begin
    Res.Send('{"erro":"Identificador invalido para exclusao"}')
       .Status(THTTPStatus.BadRequest);
    Exit;
  end;

  { Em REST rigoroso, exclusao bem-sucedida sem corpo retorna 204 }
  Res.Status(THTTPStatus.NoContent);
end;

class procedure TControllersClientes.Registry;
begin
  { Registro unificado dos endpoints RESTful do recurso Clientes }
  THorse.Get('/api/v1/clientes', @Listar);
  THorse.Get('/api/v1/clientes/:id', @ObterPorId);
  THorse.Post('/api/v1/clientes', @Criar);
  THorse.Put('/api/v1/clientes/:id', @AtualizarIntegral);
  THorse.Patch('/api/v1/clientes/:id/status', @AtualizarStatus);
  THorse.Delete('/api/v1/clientes/:id', @Excluir);
end;

end.
```

> **Atenção Thread-Safety:**  
> Ao ler `Req.Params` e `Req.Query`, o Horse cria dicionários de campos atrelados exclusivamente à instância de `THorseRequest` daquela thread de atendimento específica. Nunca tente armazenar uma referência a `Req` ou a seus dicionários em variáveis externas ou campos de classes globais. Todos os valores lidos devem ser imediatamente copiados para variáveis locais (`string`, `Integer`, `Int64`) residentes na pilha de execução (*stack*) da thread.

---

### Atualizando o Maestro de Orquestração: ConnectOSApi.lpr

Com o novo controlador construído, adicionamos a chamada `TControllersClientes.Registry;` ao programa principal:

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
  Controllers.Ping,
  Controllers.Clientes;

procedure DoOnListen;
begin
  WriteLn('----------------------------------------------------');
  WriteLn('  CONNECT OS API - ROTAS RESTFUL CARREGADAS         ');
  WriteLn('  Escutando em : http://0.0.0.0:' + IntToStr(THorse.Port));
  WriteLn('----------------------------------------------------');
end;

var
  vPorta: Word;
begin
  vPorta := StrToIntDef(GetEnvironmentVariable('PORT'), 9000);
  THorse.Port := vPorta;

  { Registro dos controladores desacoplados }
  TControllersPing.Registry;
  TControllersClientes.Registry;

  THorse.Listen(@DoOnListen);
end.
```

---

## 4. TESTANDO O ENDPOINT

Com o novo controlador compilado e ativo, realizaremos uma auditoria completa de cada verbo HTTP utilizando o utilitário `curl`.

### Teste 1: Validação de Cabeçalho Obrigatório e Paginação (GET)

Primeiramente, dispare uma chamada sem informar o cabeçalho `X-Tenant-ID`:

```bash
curl -i http://localhost:9000/api/v1/clientes
```

**Resposta do Servidor (Rejeição com 400 Bad Request):**

```http
HTTP/1.1 400 Bad Request
Content-Type: text/plain; charset=utf-8
Content-Length: 46

{"erro":"Cabecalho X-Tenant-ID e obrigatorio"}
```

Agora, execute a chamada informando o cabeçalho de Tenant e parâmetros de consulta (*query string*):

```bash
curl -i -H "X-Tenant-ID: 1" \
     -G "http://localhost:9000/api/v1/clientes" \
     -d "pagina=2&limite=5&busca=Acme"
```

**Resposta do Servidor (200 OK com Metadados):**

```http
HTTP/1.1 200 OK
Content-Type: text/plain; charset=utf-8
Content-Length: 172

{"meta":{"tenant":"1","pagina":2,"limite":5,"filtro":"Acme","total":1},
 "dados":[{"id":101,"nome_razao":"Acme Indústria",
 "cpf_cnpj":"12345678000199","ativo":true}]}
```

---

### Teste 2: Obtenção de Recurso Específico por ID na URI (GET)

Busque o cliente de identificador `42`:

```bash
curl -i http://localhost:9000/api/v1/clientes/42
```

**Resposta do Servidor:**

```http
HTTP/1.1 200 OK
Content-Type: text/plain; charset=utf-8
Content-Length: 137

{"id":42,"nome_razao":"Auto Mecanica Central LTDA",
 "cpf_cnpj":"98765432000188",
 "email":"contato@automecanica.com.br","ativo":true}
```

Simule agora a busca por um recurso inexistente (`ID 404`):

```bash
curl -i http://localhost:9000/api/v1/clientes/404
```

**Resposta do Servidor (404 Not Found):**

```http
HTTP/1.1 404 Not Found
Content-Type: text/plain; charset=utf-8
Content-Length: 32

{"erro":"Cliente nao localizado"}
```

---

### Teste 3: Criação de Recurso com Cabeçalho Location (POST)

Envie uma requisição `POST` com um corpo JSON simulado:

```bash
curl -i -X POST http://localhost:9000/api/v1/clientes \
     -H "Content-Type: application/json" \
     -d '{"nome_razao":"Novo Cliente SA","cpf_cnpj":"11222333000144"}'
```

**Resposta do Servidor (201 Created):**

```http
HTTP/1.1 201 Created
Location: /api/v1/clientes/205
Content-Type: text/plain; charset=utf-8
Content-Length: 57

{"mensagem":"Cliente cadastrado com sucesso","id":205}
```

Observe a presença do cabeçalho canônico `Location: /api/v1/clientes/205`, indicando ao cliente a URI onde o novo recurso recém-criado pode ser acessado.

---

### Teste 4: Substituição Integral (PUT) e Atualização Parcial (PATCH)

Execute o `PUT` para substituição total:

```bash
curl -i -X PUT http://localhost:9000/api/v1/clientes/205 \
     -H "Content-Type: application/json" \
     -d '{"nome_razao":"Cliente Alterado Total","ativo":true}'
```

**Resposta do Servidor (200 OK):**

```http
HTTP/1.1 200 OK
Content-Type: text/plain; charset=utf-8
Content-Length: 59

{"mensagem":"Cliente substituido integralmente","id":205}
```

Em seguida, execute o `PATCH` na subrota de status:

```bash
curl -i -X PATCH http://localhost:9000/api/v1/clientes/205/status \
     -H "Content-Type: application/json" \
     -d '{"ativo":false}'
```

**Resposta do Servidor (200 OK):**

```http
HTTP/1.1 200 OK
Content-Type: text/plain; charset=utf-8
Content-Length: 61

{"mensagem":"Status do cliente alterado via PATCH","id":205}
```

---

### Teste 5: Exclusão Idempotente de Recurso (DELETE)

Execute a exclusão do cliente:

```bash
curl -i -X DELETE http://localhost:9000/api/v1/clientes/205
```

**Resposta do Servidor (204 No Content):**

```http
HTTP/1.1 204 No Content
Date: Mon, 23 Nov 2026 11:50:00 GMT
Server: fphttpserver
```

Observe que a resposta contém o código de status HTTP `204 No Content` e **nenhum byte de corpo**, em estrito cumprimento às normas da RFC 9110.

---

## 5. ARMADILHAS COMUNS E TROUBLESHOOTING NO FPC/LAZARUS

---

### Armadilha 1: Ocorrência de Shadowing de Rotas Estáticas por Parâmetros Dinâmicos

**Sintoma:** Você cria uma rota estática para exportar dados em lote (ex: `/api/v1/clientes/relatorio`), mas ao chamá-la no navegador ou cURL, o Horse dispara indevidamente a rota de busca por ID (`/api/v1/clientes/:id`), assumindo a string `"relatorio"` como se fosse o identificador numérico do cliente!

**Causa Raiz:** A ordem de registro de rotas no framework importa. Se a rota dinâmica com parâmetro curinga (`:id`) for registrada antes da rota estática com caminho literal, o avaliador de rotas pode considerar a rota com curinga como primeira correspondência (*first match*).

**Solução Definitiva:** Sempre registre todas as rotas estáticas e especializadas **antes** das rotas dinâmicas parametrizadas:

```pascal
{ ORDEM CORRETA DE REGISTRO }
THorse.Get('/api/v1/clientes/relatorio', @GerarRelatorio); { Estatica }
THorse.Get('/api/v1/clientes/:id', @ObterPorId);           { Dinamica }
```

---

### Armadilha 2: Exceção EConvertError por Falta de Sanitização Numérica

**Sintoma:** Um usuário mal-intencionado ou um bot de varredura dispara uma requisição passando texto onde se esperava um inteiro (ex: `GET /api/v1/clientes/abc`). O servidor sofre um crash de execução com a exceção:

```text
EConvertError: "abc" is an invalid integer
```

**Causa Raiz:** Utilizar funções de conversão estritas do Free Pascal (como `StrToInt` ou `StrToInt64`) diretamente sobre valores oriundos de `Req.Params` sem proteção de tratamento de erro.

**Solução:** Utilize funções defensivas de conversão com valor padrão de contingência (`StrToIntDef` ou `StrToInt64Def`):

```pascal
{ CORRETO E DEFENSIVO }
vClienteId := StrToInt64Def(Req.Params.Field('id').AsString, 0);
if vClienteId <= 0 then
begin
  Res.Send('{"erro":"Identificador numerico invalido"}')
     .Status(THTTPStatus.BadRequest);
  Exit;
end;
```

---

### Armadilha 3: Ignorar que Cabeçalhos HTTP são Case-Insensitive

**Sintoma:** Um frontend SPA desenvolvido em Angular/React envia o cabeçalho `x-tenant-id` em letras minúsculas (padrão imposto pelo protocolo HTTP/2), mas o código em Pascal tenta ler estritamente `Req.Headers.Field('X-Tenant-ID')` e não encontra o valor.

**Causa Raiz:** Comparação de strings que diferenciam maiúsculas e minúsculas (*case-sensitive*) ao manipular a lista de cabeçalhos.

**Solução:** O Horse implementa a busca em dicionários de cabeçalho de forma agnóstica a maiúsculas e minúsculas. Porém, se o desenvolvedor iterar manualmente pela coleção de headers ou acessar o objeto bruto `Req.RawWebRequest`, deve sempre utilizar funções agnósticas como `SameText` ou normalizar a chave para minúsculas antes da checagem.

---

## 6. RESUMO EXECUTIVO E CHECKLIST DE REVISÃO

### Matriz de Roteamento RESTful

| Ação Pretendida | Verbo HTTP | Rota Canônica | Parâmetros Chave | Status HTTP Esperado |
| :--- | :--- | :--- | :--- | :--- |
| **Listar Clientes** | `GET` | `/api/v1/clientes` | `Req.Query` (pagina, limite) | `200 OK` |
| **Consultar Cliente**| `GET` | `/api/v1/clientes/:id`| `Req.Params` (id) | `200 OK` / `404 Not Found` |
| **Cadastrar Cliente**| `POST`| `/api/v1/clientes` | `Req.Body` (JSON) | `201 Created` + `Location` |
| **Substituição Total**| `PUT` | `/api/v1/clientes/:id`| `Req.Params` + `Req.Body` | `200 OK` |
| **Alteração Parcial**| `PATCH`| `/api/v1/clientes/:id/status`| `Req.Params` + `Req.Body` | `200 OK` |
| **Exclusão** | `DELETE`| `/api/v1/clientes/:id`| `Req.Params` (id) | `204 No Content` |

---

### Checklist de Revisão e Auditoria Técnica

Antes de avançar para o Módulo 04, certifique-se de validar todos os itens da lista:

- [ ] **Semântica de Verbos:** As operações de leitura utilizam exclusivamente `GET`, as de criação `POST`, substituições integrais `PUT`, mutações parciais `PATCH` e remoções `DELETE`.
- [ ] **Prevenção de Shadowing:** Rotas com caminhos literais fixos foram registradas antes de rotas com variáveis dinâmicas (`:id`).
- [ ] **Conversão Defensiva de Parâmetros:** Todas as leituras numéricas de `Req.Params` e `Req.Query` utilizam `StrToIntDef` ou `StrToInt64Def`, impedindo o estouro de exceções `EConvertError`.
- [ ] **Respeito à Idempotência:** As rotas `PUT` e `DELETE` foram implementadas respeitando o conceito de que chamadas repetidas produzem o mesmo estado final.
- [ ] **Cabeçalho Location:** As operações de criação (`POST`) emitem o cabeçalho `Location` com a URI de consulta do novo recurso gerado.
- [ ] **Ausência de Corpo no 204:** A rota `DELETE` retorna status `204 No Content` sem corpo de resposta associado.

Com o domínio pleno das técnicas de roteamento e extração de parâmetros no Horse, avançamos agora para o **Módulo 04**, onde dissecaremos o ciclo de vida completo de requisições e respostas, os códigos de status HTTP e a implementação formal do padrão **RFC 7807 (Problem Details)** para tratamento padronizado de erros.
