# MÓDULO 09: ARQUITETURA LIMPA, MVC E INTERFACES NO LAZARUS

---

## 1. OBJETIVOS DE APRENDIZAGEM DO MÓDULO

Ao final deste módulo, você será capaz de:

1. Aplicar os princípios da **Clean Architecture** (Arquitetura Limpa) e os fundamentos **SOLID** no ecossistema Object Pascal moderno com o Free Pascal Compiler (FPC) e o Lazarus.
2. Projetar a separação estrita de responsabilidades entre as quatro camadas essenciais: **Controladores HTTP (Horse)**, **Serviços de Negócio (Services)**, **Acesso a Dados (Repositories)** e **Objetos de Transferência (DTOs)**.
3. Eliminar em definitivo o erro fatal de **dependência circular entre units (*Circular Unit Dependency*)**, estruturando contratos formais em units isoladas de interfaces.
4. Dominar o mecanismo de gerenciamento automático de memória por contagem de referências (*Reference Counting*) com **`IInterface`** e **`TInterfacedObject`** (`_AddRef` e `_Release`).
5. Implementar **Inversão de Controle (IoC)** e Injeção de Dependências manual via construtores, viabilizando a substituição transparente de repositórios em testes e desacoplando as regras de negócio de drivers de banco.

---

## 2. FUNDAMENTAÇÃO CONCEITUAL E ARQUITETURAL

Historicamente, o desenvolvimento de software corporativo no ecossistema Pascal foi marcado pelo uso intensivo de componentes visuais do tipo RAD (*Rapid Application Development*). Era comum desenvolvedores arrastarem componentes de conexão de banco (`TIBConnection`, `ZConnection`) e queries (`TSQLQuery`, `ZQuery`) diretamente para dentro de um `DataModule`, acoplando no mesmo arquivo a interface gráfica, a lógica de validação de crédito e as instruções SQL de persistência.

Esse estilo arquitetural artesanal — frequentemente denominado *"Smart UI"* ou *"código espaguete"* — torna-se catastrófico ao construir APIs web modernas:
- **Impossibilidade de Testes Automatizados:** Não é possível testar uma regra de negócio sem instanciar um banco de dados real e uma conexão de rede.
- **Acoplamento Extremo ao Framework Web:** Se o controlador Horse manipula diretamente conexões com o banco, qualquer mudança no transporte (como migrar de HTTP para mensageria RabbitMQ ou gRPC) exige reescrever a aplicação inteira.
- **Risco de Corrupção Concorrente:** Componentes visuais e DataModules tradicionais não foram projetados para serem compartilhados entre múltiplas threads concorrentes.

Para construir sistemas corporativos de classe mundial, adotamos os preceitos da **Arquitetura Limpa** formulados por Robert C. Martin (*Uncle Bob*), adaptados à semântica rigorosa do Free Pascal.

```
+-------------------------------------------------------------------+
|               CAMADAS DA ARQUITETURA LIMPA NO HORSE               |
+-------------------------------------------------------------------+
|                                                                   |
| [ CAMADA EXTERNA: INFRAESTRUTURA & TRANSPORTE ]                   |
|   - Controllers Horse (HTTP, Rotas, JSON, Status Codes)           |
|                                                                   |
| [ CAMADA DE APLICAÇÃO: CASOS DE USO & REGRAS ]                    |
|   - Services (IClienteService - Validações, Cálculos, Fluxos)     |
|                                                                   |
| [ CAMADA DE CONTRATOS & ABSTRAÇÕES ]                              |
|   - Interfaces (IClienteRepository, IUnitOfWork)                  |
|                                                                   |
| [ CAMADA DE PERSISTÊNCIA & DADOS ]                                |
|   - Repositories (Firebird 5.0 SQL, ZeosLib, SQLdb)               |
|                                                                   |
+-------------------------------------------------------------------+
```

### O Princípio de Inversão de Dependência (DIP)

O quinto princípio SOLID — **Princípio da Inversão de Dependência (Dependency Inversion Principle)** — estabelece duas regras invioláveis:
1. *Módulos de alto nível não devem depender de módulos de baixo nível. Ambos devem depender de abstrações.*
2. *Abstrações não devem depender de detalhes. Detalhes devem depender de abstrações.*

Na prática, isso significa que a nossa classe de serviço `TClienteService` (alto nível) **nunca** deve instanciar diretamente `TClienteRepositoryFirebird` (baixo nível). Em vez disso, a Service deve receber em seu construtor uma referência puramente contratual: a interface **`IClienteRepository`**.

Se amanhã decidirmos substituir o Firebird por PostgreSQL, ou se quisermos rodar um teste unitário com um repositório simulado em memória (*Mock*), o código da Service permanecerá rigorosamente intocado.

### Eliminando Dependências Circulares no FPC

No compilador Free Pascal, cada arquivo `.pas` é uma unidade modular compilada separadamente. Se a unit `A` declara a unit `B` em sua seção `interface`, e a unit `B` declara a unit `A` em sua seção `interface`, o compilador FPC aborta imediatamente o processo com a falha:

```text
Fatal: Circular dependency between A and B
```

A solução de engenharia definitiva para erradicar dependências circulares consiste em criar uma pasta dedicada **`src/Interfaces/`** contendo units que declaram **exclusivamente contratos de interface e DTOs puros**. Nenhuma unit de interface jamais referencia uma unit de Service, Repository ou Controller. Todas as camadas superiores dependem da camada de Interfaces, mas as interfaces dependem de ninguém.

```
       +-----------------------+
       |   Controllers Horse   |
       +-----------------------+
                   |
                   v (Depende de)
       +-----------------------+
       |   IClienteService     | <----+ (Implementa)
       +-----------------------+      |
                   ^                  |
                   | (Depende de)     |
       +-----------------------+      |
       |   IClienteRepository  |      |
       +-----------------------+      |
                   ^                  |
                   | (Implementa)     |
       +-----------------------+  +-----------------------+
       | Repositorio Firebird  |  |  TClienteService      |
       +-----------------------+  +-----------------------+
```

### Gerenciamento de Memória com IInterface e TInterfacedObject

Uma das características mais poderosas do Free Pascal é o suporte nativo ao modelo de interfaces compatível com o padrão COM da Microsoft.

No FPC, qualquer interface declarada como descendente de `IInterface` (ou `IUnknown`) possui três métodos fundamentais:
```pascal
function _AddRef: LongInt; stdcall;
function _Release: LongInt; stdcall;
function QueryInterface(constref iid: TGUID; out obj): HResult; stdcall;
```

Quando uma classe herda de **`TInterfacedObject`**, a biblioteca do FPC implementa automaticamente esses métodos através de um contador interno de referências (*Reference Counting*):
1. **Atribuição:** Toda vez que você atribui uma instância a uma variável de interface (ex: `vRepo: IClienteRepository := TClienteRepository.Create;`), o compilador insere nos bastidores uma chamada a `_AddRef`, incrementando o contador em 1.
2. **Saída de Escopo:** Quando o procedimento ou método onde a variável de interface foi declarada chega ao seu `end;` final, o compilador insere uma chamada a `_Release`, decrementando o contador em 1.
3. **Autodestruição Determinística:** No instante em que o contador de referências chega a **zero**, o próprio método `_Release` invoca `Self.Destroy`.

> **Boas Práticas FPC:**  
> Ao trabalhar com instâncias gerenciadas por interfaces, **nunca invoque o método `.Free` manualmente**. Deixe que o mecanismo de contagem de referências do Free Pascal desaloque a memória automaticamente. Invocar `.Free` em um objeto que ainda possui referências ativas de interface causará violações de acesso (*SIGSEGV*) no momento em que a variável sair de escopo e o FPC tentar decrementar o contador de uma instância já destruída.

---

## 3. IMPLEMENTAÇÃO PASSO A PASSO

Construiremos agora a espinha dorsal desacoplada da entidade **Cliente** no projeto **ConnectOSApi**:
1. `Interfaces.Cliente.pas`: Contratos canônicos de repositório e serviço.
2. `Repositories.Cliente.pas`: Repositório concreto implementando `IClienteRepository` (simulando a camada de dados em memória antes da conexão física com o Firebird).
3. `Services.Cliente.pas`: Serviço de negócio puro implementando `IClienteService` com injeção de dependência via construtor.
4. Refatoração de `Controllers.Clientes.pas` consumindo a interface da Service.

### Passo 1: Definindo os Contratos: Interfaces.Cliente.pas

Crie a unit `src/Interfaces/Interfaces.Cliente.pas` respeitando rigorosamente o limite de 72 caracteres por linha:

```pascal
{======================================================================}
{ Projeto: ConnectOSApi - API de Gestao e Faturamento Multi-Tenant     }
{ Unit   : Interfaces.Cliente                                          }
{ Papel  : Contratos abstratos para Repositorios e Servicos de Cliente }
{======================================================================}
unit Interfaces.Cliente;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  DTOs.Cliente;

type
  { Contrato para acesso a dados de Clientes }
  IClienteRepository = interface
    ['{8A5D6E7F-1B2C-3D4E-5F6A-7B8C9D0E1F2A}']
    function Listar(ATenantId: Int64; APagina, ALimite: Integer; 
      const ABusca: string): TList;
    function ObterPorId(ATenantId, AClienteId: Int64): TClienteDTO;
    function ObterPorDocumento(ATenantId: Int64; 
      const ADocumento: string): TClienteDTO;
    function Inserir(ATenantId: Int64; AInput: TClienteInputDTO): Int64;
    procedure Atualizar(ATenantId, AClienteId: Int64; 
      AInput: TClienteInputDTO);
    procedure Excluir(ATenantId, AClienteId: Int64);
  end;

  { Contrato para regras de negocio de Clientes }
  IClienteService = interface
    ['{9B6E7F8A-2C3D-4E5F-6A7B-8C9D0E1F2A3B}']
    function ListarClientes(ATenantId: Int64; 
      APagina, ALimite: Integer; const ABusca: string): TList;
    function ObterCliente(ATenantId, AClienteId: Int64): TClienteDTO;
    function CadastrarCliente(ATenantId: Int64; 
      AInput: TClienteInputDTO): Int64;
    procedure AtualizarCliente(ATenantId, AClienteId: Int64; 
      AInput: TClienteInputDTO);
    procedure RemoverCliente(ATenantId, AClienteId: Int64);
  end;

implementation

end.
```

---

### Passo 2: Implementando o Repositório: Repositories.Cliente.pas

Crie a unit `src/Repositories/Repositories.Cliente.pas`. Observe a herança obrigatória de `TInterfacedObject`:

```pascal
{======================================================================}
{ Projeto: ConnectOSApi - API de Gestao e Faturamento Multi-Tenant     }
{ Unit   : Repositories.Cliente                                        }
{ Papel  : Implementacao concreta do repositorio de Clientes           }
{======================================================================}
unit Repositories.Cliente;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  Interfaces.Cliente,
  DTOs.Cliente;

type
  { Repositorio de Clientes implementando IClienteRepository }
  TClienteRepository = class(TInterfacedObject, IClienteRepository)
  public
    function Listar(ATenantId: Int64; APagina, ALimite: Integer; 
      const ABusca: string): TList;
    function ObterPorId(ATenantId, AClienteId: Int64): TClienteDTO;
    function ObterPorDocumento(ATenantId: Int64; 
      const ADocumento: string): TClienteDTO;
    function Inserir(ATenantId: Int64; AInput: TClienteInputDTO): Int64;
    procedure Atualizar(ATenantId, AClienteId: Int64; 
      AInput: TClienteInputDTO);
    procedure Excluir(ATenantId, AClienteId: Int64);
  end;

implementation

{ TClienteRepository }

function TClienteRepository.Listar(ATenantId: Int64; 
  APagina, ALimite: Integer; const ABusca: string): TList;
var
  vDTO: TClienteDTO;
begin
  Result := TList.Create;

  { Simulacao de registros recuperados da base }
  vDTO := TClienteDTO.Create;
  vDTO.Id := 101;
  vDTO.NomeRazao := 'Conect Solutions TI LTDA';
  vDTO.CPFCNPJ := '12345678000199';
  vDTO.Email := 'contato@conectsolutions.com';
  vDTO.Telefone := '(11) 98888-7777';
  vDTO.Ativo := True;
  Result.Add(vDTO);
end;

function TClienteRepository.ObterPorId(ATenantId, 
  AClienteId: Int64): TClienteDTO;
begin
  Result := nil;
  if AClienteId = 404 then
    Exit;

  Result := TClienteDTO.Create;
  Result.Id := AClienteId;
  Result.NomeRazao := 'Cliente Recuperado do Repositorio';
  Result.CPFCNPJ := '12345678000199';
  Result.Email := 'cliente@repositorio.com';
  Result.Telefone := '(11) 3333-4444';
  Result.Ativo := True;
end;

function TClienteRepository.ObterPorDocumento(ATenantId: Int64; 
  const ADocumento: string): TClienteDTO;
begin
  Result := nil;
  { Simula que o documento 11111111000199 ja existe }
  if Pos('11111111000199', ADocumento) > 0 then
  begin
    Result := TClienteDTO.Create;
    Result.Id := 999;
    Result.NomeRazao := 'Cliente Duplicado Existente';
    Result.CPFCNPJ := ADocumento;
  end;
end;

function TClienteRepository.Inserir(ATenantId: Int64; 
  AInput: TClienteInputDTO): Int64;
begin
  { Simula geracao de ID via IDENTITY do Firebird 5.0 }
  Result := 501;
end;

procedure TClienteRepository.Atualizar(ATenantId, AClienteId: Int64; 
  AInput: TClienteInputDTO);
begin
  { Simula comando UPDATE na base }
end;

procedure TClienteRepository.Excluir(ATenantId, AClienteId: Int64);
begin
  { Simula comando DELETE na base }
end;

end.
```

---

### Passo 3: Implementando a Regra de Negócio: Services.Cliente.pas

A unit `src/Services/Services.Cliente.pas` aplica as regras de negócio puras (validação de documento, checagem de duplicidade) e depende **estritamente** da interface `IClienteRepository`:

```pascal
{======================================================================}
{ Projeto: ConnectOSApi - API de Gestao e Faturamento Multi-Tenant     }
{ Unit   : Services.Cliente                                            }
{ Papel  : Regras de negocio e orquestracao da entidade Cliente        }
{======================================================================}
unit Services.Cliente;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  Interfaces.Cliente,
  DTOs.Cliente,
  Core.Exceptions;

type
  { Servico de Dominio para Gestao de Clientes }
  TClienteService = class(TInterfacedObject, IClienteService)
  private
    FRepository: IClienteRepository;
  public
    constructor Create(ARepository: IClienteRepository);
    function ListarClientes(ATenantId: Int64; 
      APagina, ALimite: Integer; const ABusca: string): TList;
    function ObterCliente(ATenantId, AClienteId: Int64): TClienteDTO;
    function CadastrarCliente(ATenantId: Int64; 
      AInput: TClienteInputDTO): Int64;
    procedure AtualizarCliente(ATenantId, AClienteId: Int64; 
      AInput: TClienteInputDTO);
    procedure RemoverCliente(ATenantId, AClienteId: Int64);
  end;

implementation

{ TClienteService }

constructor TClienteService.Create(ARepository: IClienteRepository);
begin
  inherited Create;
  { INJECAO DE DEPENDENCIA: A Service armazena a interface }
  FRepository := ARepository;
end;

function TClienteService.ListarClientes(ATenantId: Int64; 
  APagina, ALimite: Integer; const ABusca: string): TList;
begin
  if ATenantId <= 0 then
    raise EBusinessException.Create('Tenant invalido para listagem');

  if ALimite > 100 then
    ALimite := 100; { Protecao contra paginacao abusiva }

  Result := FRepository.Listar(ATenantId, APagina, ALimite, ABusca);
end;

function TClienteService.ObterCliente(ATenantId, 
  AClienteId: Int64): TClienteDTO;
begin
  if AClienteId <= 0 then
    raise EBusinessException.Create(
      'Identificador de cliente invalido');

  Result := FRepository.ObterPorId(ATenantId, AClienteId);
  if not Assigned(Result) then
    raise ENotFoundException.Create('Cliente nao localizado na base');
end;

function TClienteService.CadastrarCliente(ATenantId: Int64; 
  AInput: TClienteInputDTO): Int64;
var
  vExistente: TClienteDTO;
begin
  if not Assigned(AInput) then
    raise EBusinessException.Create('Dados do cliente ausentes');

  if Trim(AInput.NomeRazao) = '' then
    raise EBusinessException.Create('Razao Social e campo obrigatorio');

  if Length(Trim(AInput.CPFCNPJ)) < 11 then
    raise EBusinessException.Create('Documento CPF/CNPJ invalido');

  { Checagem de unicidade atraves do repositorio }
  vExistente := FRepository.ObterPorDocumento(
    ATenantId, AInput.CPFCNPJ);
  if Assigned(vExistente) then
  begin
    vExistente.Free;
    raise EConflictException.Create(
      'Ja existe um cliente cadastrado com este CPF/CNPJ');
  end;

  Result := FRepository.Inserir(ATenantId, AInput);
end;

procedure TClienteService.AtualizarCliente(
  ATenantId, AClienteId: Int64; AInput: TClienteInputDTO);
var
  vAtual: TClienteDTO;
begin
  vAtual := ObterCliente(ATenantId, AClienteId);
  vAtual.Free;

  FRepository.Atualizar(ATenantId, AClienteId, AInput);
end;

procedure TClienteService.RemoverCliente(ATenantId, AClienteId: Int64);
var
  vAtual: TClienteDTO;
begin
  vAtual := ObterCliente(ATenantId, AClienteId);
  vAtual.Free;

  FRepository.Excluir(ATenantId, AClienteId);
end;

end.
```

---

### Passo 4: Refatorando o Controlador Horse: Controllers.Clientes.pas

O controlador agora atua como uma casca fina de transporte HTTP, delegando toda a lógica para a interface `IClienteService`:

```pascal
unit Controllers.Clientes;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  fpjson,
  Horse,
  Interfaces.Cliente,
  Services.Cliente,
  Repositories.Cliente,
  DTOs.Cliente,
  Core.Exceptions;

type
  TControllersClientes = class
  private
    class function CriarService: IClienteService; static;
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

class function TControllersClientes.CriarService: IClienteService;
begin
  { Factory leve: instancia o repositorio e injeta na Service }
  Result := TClienteService.Create(TClienteRepository.Create);
end;

class procedure TControllersClientes.Listar(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vService: IClienteService;
  vTenantId: Int64;
  vLista: TList;
  vEnvelope: TJSONObject;
  vItens: TJSONArray;
  i: Integer;
begin
  vTenantId := StrToInt64Def(
    Req.Headers.Field('X-Tenant-ID').AsString, 1);

  vService := CriarService;
  vLista := vService.ListarClientes(vTenantId, 1, 10, '');
  try
    vEnvelope := TJSONObject.Create;
    vItens := TJSONArray.Create;

    for i := 0 to vLista.Count - 1 do
      vItens.Add(TClienteDTO(vLista[i]).ToJSONObject);

    vEnvelope.Add('total', vLista.Count);
    vEnvelope.Add('dados', vItens);

    Res.Send(vEnvelope)
       .Status(THTTPStatus.OK);
  finally
    for i := 0 to vLista.Count - 1 do
      TClienteDTO(vLista[i]).Free;
    vLista.Free;
  end;
end;

class procedure TControllersClientes.ObterPorId(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vService: IClienteService;
  vTenantId, vClienteId: Int64;
  vDTO: TClienteDTO;
begin
  vTenantId := 1;
  vClienteId := StrToInt64Def(Req.Params.Field('id').AsString, 0);

  vService := CriarService;
  vDTO := vService.ObterCliente(vTenantId, vClienteId);
  try
    Res.Send(vDTO.ToJSONObject)
       .Status(THTTPStatus.OK);
  finally
    vDTO.Free;
  end;
end;

class procedure TControllersClientes.Criar(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vService: IClienteService;
  vInputJSON: TJSONObject;
  vInputDTO: TClienteInputDTO;
  vNovoId: Int64;
  vResposta: TJSONObject;
begin
  vInputJSON := Req.Body<TJSONObject>();
  if not Assigned(vInputJSON) then
    raise EAppException.Create('Payload JSON ausente', 400);

  vInputDTO := TClienteInputDTO.FromJSONObject(vInputJSON);
  try
    vService := CriarService;
    vNovoId := vService.CadastrarCliente(1, vInputDTO);

    vResposta := TJSONObject.Create;
    vResposta.Add('id', vNovoId);
    vResposta.Add('mensagem', 'Cadastrado via Clean Architecture');

    Res.RawWebResponse.SetCustomHeader('Location', 
      '/api/v1/clientes/' + IntToStr(vNovoId));

    Res.Send(vResposta)
       .Status(THTTPStatus.Created);
  finally
    vInputDTO.Free;
  end;
end;

class procedure TControllersClientes.Excluir(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vService: IClienteService;
  vClienteId: Int64;
begin
  vClienteId := StrToInt64Def(Req.Params.Field('id').AsString, 0);
  vService := CriarService;
  vService.RemoverCliente(1, vClienteId);

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

Com a Arquitetura Limpa em vigor, vamos validar o comportamento dos endpoints e a interceptação transparente das exceções de serviço via `curl`.

### Teste 1: Cadastro com Sucesso através da Service e Repositório (POST)

Cadastre um novo cliente válido:

```bash
curl -i -X POST http://localhost:9000/api/v1/clientes \
     -H "Content-Type: application/json" \
     -d '{"nome_razao":"Auto Eletrica Pioneira",
          "cpf_cnpj":"22333444000188"}'
```

**Resposta do Servidor (201 Created):**

```http
HTTP/1.1 201 Created
Location: /api/v1/clientes/501
Content-Type: application/json; charset=utf-8
Content-Length: 68

{"id":501,"mensagem":"Cadastrado via Clean Architecture"}
```

A requisição transitou pelo Controller -> Service (validações) -> Repository (persistência simulada) e retornou com sucesso.

---

### Teste 2: Validação de Regra de Negócio na Service (422)

Tente cadastrar um cliente sem informar a Razão Social:

```bash
curl -i -X POST http://localhost:9000/api/v1/clientes \
     -H "Content-Type: application/json" \
     -d '{"nome_razao":"","cpf_cnpj":"22333444000188"}'
```

**Resposta da Service Interceptada pelo Middleware Global (422):**

```http
HTTP/1.1 422 Unprocessable Entity
Content-Type: application/problem+json; charset=utf-8
Content-Length: 268

{"type":"https://api.connectos.com/erros/regra_negocio_violada",
 "title":"EBusinessException",
 "status":422,
 "detail":"Razao Social e campo obrigatorio",
 "instance":"/api/v1/clientes"}
```

---

### Teste 3: Checagem de Conflito de Unicidade na Service (409)

Envie o documento duplicado `11111111000199`:

```bash
curl -i -X POST http://localhost:9000/api/v1/clientes \
     -H "Content-Type: application/json" \
     -d '{"nome_razao":"Cliente Teste Duplicado",
          "cpf_cnpj":"11111111000199"}'
```

**Resposta de Conflito (409 Conflict):**

```http
HTTP/1.1 409 Conflict
Content-Type: application/problem+json; charset=utf-8
Content-Length: 288

{"type":"https://api.connectos.com/erros/conflito_estado",
 "title":"EConflictException",
 "status":409,
 "detail":"Ja existe um cliente cadastrado com este CPF/CNPJ",
 "instance":"/api/v1/clientes"}
```

---

## 5. ARMADILHAS COMUNS E TROUBLESHOOTING NO FPC/LAZARUS

---

### Armadilha 1: Misturar Ponteiros de Objeto Puro com Interfaces

**Sintoma:** Violação de acesso (*SIGSEGV*) aleatória ao sair de um procedimento onde uma interface e um objeto concreto foram utilizados simultaneamente.

**Causa Raiz:** O desenvolvedor instancia a classe em uma variável concreta e atribui à interface, invocando `.Free` na variável concreta:

```pascal
{ EQUIVOCO GRAVE: Dangling Pointer }
var
  vObj: TClienteRepository;
  vIntf: IClienteRepository;
begin
  vObj := TClienteRepository.Create;
  vIntf := vObj; { Contador de ref = 1 }
  vObj.Free;     { Destroi o objeto manualmente! }
  { Ao sair, vIntf chama _Release e acessa memoria morta }
end;
```

**Solução:** Ao utilizar interfaces, atribua **diretamente** o resultado de `.Create` à variável de interface, sem variáveis intermediárias de classe:

```pascal
var
  vIntf: IClienteRepository;
begin
  vIntf := TClienteRepository.Create; { 100% seguro }
end;
```

---

### Armadilha 2: Esquecer de Herdar de TInterfacedObject

**Sintoma:** O compilador acusa erro de métodos abstratos não implementados:

```text
Error: No matching implementation for interface method "_AddRef" found
```

**Causa Raiz:** A classe foi declarada como `class(TObject, IMinhaInterface)`. O `TObject` básico não implementa `_AddRef`, `_Release` e `QueryInterface`.

**Solução:** Todas as classes que implementam interfaces no FPC devem herdar de `TInterfacedObject`:

```pascal
type
  TMeuServico = class(TInterfacedObject, IMeuServico)
```

---

### Armadilha 3: Dependência Circular por Falta de Camada de Contratos

**Sintoma:** O arquivo `Services.Cliente.pas` tenta referenciar `Controllers.Clientes.pas` e o compilador aborta com `Fatal: Circular dependency`.

**Causa Raiz:** Comunicação bidirecional desordenada entre camadas superiores e inferiores.

**Solução:** A camada de controladores pode enxergar a camada de serviços, mas a camada de serviços **nunca** deve enxergar a camada de controladores. Todas as referências cruzadas devem transitar pelas units de `Interfaces/`.

---

## 6. RESUMO EXECUTIVO E CHECKLIST DE REVISÃO

### Matriz de Responsabilidades da Arquitetura Limpa

| Camada | Papel Arquitetural | O que DEVE Conhecer | O que NÃO DEVE Conhecer |
| :--- | :--- | :--- | :--- |
| **Controllers** | Transporte HTTP / Rotas | Horse, DTOs, Interfaces de Service | SQL, Firebird, Conexões |
| **Services** | Regras de Negócio e Casos de Uso | Interfaces de Repo, DTOs, Exceções | Horse, HTTP, Status Codes |
| **Repositories** | Persistência e Acesso a Dados | Firebird 5.0, SQL, Interfaces de Repo| Horse, Regras de Negócio |
| **Interfaces** | Contratos de Desacoplamento | DTOs e Tipos primitivos | Nenhuma outra camada |

---

### Checklist de Revisão e Auditoria Técnica

Antes de avançar para o Módulo 10, certifique-se de validar os seguintes itens:

- [ ] **Zero Dependências Circulares:** As units de interfaces (`src/Interfaces/`) não declaram referências a Controllers ou Services.
- [ ] **Herança de TInterfacedObject:** Todas as classes que implementam interfaces herdam de `TInterfacedObject`.
- [ ] **Contagem de Referências:** Nenhuma variável atribuída a interfaces invoca `.Free` manualmente.
- [ ] **Inversão de Dependências:** O serviço `TClienteService` recebe `IClienteRepository` em seu construtor.
- [ ] **Desacoplamento de Erros:** As regras de negócio na Service lançam exceções tipadas de domínio (`EBusinessException`, `EConflictException`), sem tocar em HTTP.

Com a arquitetura limpa e desacoplada plenamente implantada, avançamos para o **Módulo 10**, onde mergulharemos a fundo na modelagem física e nos recursos nativos de alto desempenho do **Firebird 5.0**.
