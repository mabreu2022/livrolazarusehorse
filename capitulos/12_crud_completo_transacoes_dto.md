# Módulo 12: CRUD Completo, Transações Explícitas e Padrão Unit of Work

Neste módulo, consolidaremos os alicerces construídos até aqui para 
erguer a espinha dorsal de nossa aplicação comercial: a gestão de Ordens 
de Serviço (OS) e seus respectivos itens em um ecossistema multi-tenant. 
Diferente de cadastros simples de tabela única, operações que envolvem 
cabeçalho e múltiplos registros filhos exigem atomicidade absoluta. Se 
um item falhar, nenhum dado pode ser persistido. 

Exploraremos em profundidade o ciclo de vida transacional no Firebird 
5.0 acoplado ao ecossistema Free Pascal, implementando o padrão Unit of 
Work (Unidade de Trabalho), validações de consistência em Data Transfer 
Objects (DTOs) e tratamento rigoroso de integridade referencial.

---

## 1. Objetivos de Aprendizagem do Módulo

Ao concluir este módulo, o leitor estará plenamente capacitado a:
1. Projetar e implementar o fluxo completo de CRUD relacional mestre-detalhe 
   (Ordem de Serviço e Itens) sob os preceitos da Arquitetura Limpa.
2. Aplicar o padrão Unit of Work no Object Pascal com `SQLdb` e `IBConnection`, 
   orquestrando transações atômicas com `StartTransaction`, `Commit` e `Rollback`.
3. Compreender a diferença crítica entre `Commit` e `CommitRetaining` no 
   motor de MVCC do Firebird 5.0 e o impacto direto na coleta de lixo (*garbage 
   collection*) e avanço da OAT (*Oldest Active Transaction*).
4. Estruturar DTOs de entrada e saída ricos em validações de domínio antes de 
   qualquer interação com o banco de dados.
5. Controlar a máquina de estados de uma Ordem de Serviço (Aberta, Em 
   Execução, Concluída, Cancelada), impedindo alterações proibidas.
6. Isolar totalmente as operações por Tenant (`tenant_id`), prevenindo vazamento 
   acidental de dados entre clientes distintos.

---

## 2. Fundamentação Conceitual e Arquitetural

### 2.1 O Ciclo Transacional ACID no Firebird 5.0

Em sistemas web concorrentes, a integridade dos dados depende da 
disciplina com que as transações são tratadas. No Firebird, cada comando 
SQL de leitura ou escrita deve obrigatoriamente residir dentro de um 
contexto transacional ativo (`TSQLTransaction`). 

Para o nosso cenário de APIs REST, adotamos a configuração de transação 
com isolamento `READ COMMITTED` e resolução de conflito `NOWAIT`:

```
+--------------------------------------------------------------------+
| PARAMETROS DO TSQLTransaction (READ COMMITTED + NOWAIT)            |
|                                                                    |
| isc_tpb_read_committed : Enxerga dados commitados por outros       |
| isc_tpb_rec_version    : Le versao mais recente sem lock de leitura|
| isc_tpb_nowait         : Retorna erro de lock de imediato (sem hang)|
+--------------------------------------------------------------------+
```

Essa combinação garante que uma requisição HTTP nunca fique congelada 
esperando um lock de linha indefinidamente. Se outra thread estiver 
alterando o mesmo registro de estoque ou fatura, a transação recebe um erro 
imediato, que é capturado pelo nosso middleware de exceções e convertido 
em `409 Conflict` ou `422 Unprocessable Entity`.

> **Atenção Thread-Safety:**
> No modelo multi-threaded do `fphttpserver`, nunca reutilize uma instância 
> de `TSQLTransaction` entre threads. Cada transação pertence exclusivamente 
> à sua respectiva conexão física adquirida do Pool. Transações compartilhadas 
> causam corrupção de ponteiros internos da `fbclient` e abortam o processo.

### 2.2 O Perigo Fatal do `CommitRetaining` em APIs REST

Desenvolvedores Delphi/Lazarus migrando do desenvolvimento desktop clássico 
para o ambiente web frequentemente cometem o erro grave de invocar 
`Transaction.CommitRetaining` em vez de `Transaction.Commit`. 

No Firebird, `CommitRetaining` persiste as alterações no disco, mas **mantém 
o contexto da transação aberto**, preservando a mesma Transaction ID (TID). 
Em uma API de alta taxa de requisições, isso impede que a OAT (*Oldest Active 
Transaction*) avance. Como consequência:
1. O processo de Garbage Collection do Firebird é paralisado.
2. As versões antigas dos registros acumuladas em disco não são expurgadas.
3. O arquivo de banco de dados (`.fdb`) incha rapidamente e a performance 
   geral do servidor colapsa em poucas horas.

> **Boas Práticas FPC:**
> Em servidores de API REST, **jamais utilize `CommitRetaining`**. Toda 
> transação deve ter um ciclo de vida curto: `StartTransaction` -> Execução 
> de SQLs -> `Commit` (ou `Rollback` na cláusula `except`).

### 2.3 O Padrão Unit of Work

O padrão Unit of Work mantém uma lista de objetos afetados por uma transação 
de negócios e coordena a gravação dessas alterações e a resolução de 
problemas de concorrência. Na nossa implementação em Lazarus, o Unit of Work 
encapsula o `IConnectionWrapper`, garantindo que os repositórios de 
`OrdemServico` e `ItemOrdemServico` operem exatamente sobre a mesma conexão 
e transação física:

```
+--------------------------------------------------------------------+
|                    Unit of Work (IUnitOfWork)                      |
|  - Gerencia IConnectionWrapper obtido atomicamente do Pool         |
|  - Inicia transacao explicita (StartTransaction)                   |
|  - Repassa conexao/transacao para Repositories dependentes         |
|  - Efetua Commit ou Rollback garantido via try..finally            |
+--------------------------------------------------------------------+
                                   |
         +-------------------------+-------------------------+
         |                                                   |
         v                                                   v
+-------------------------------+   +-------------------------------+
|   IOrdemServicoRepository     |   |     IItemOrdemServicoRepo     |
|   Persiste cabecalho da OS    |   |   Persiste itens e servicos   |
|   (INSERT INTO ordens_servico)|   |   (INSERT INTO itens_os)      |
+-------------------------------+   +-------------------------------+
```

---

## 3. Implementação Passo a Passo

### 3.1 Contratos de Dados (DTOs)

Criaremos a unit `DTOs.OrdemServico.pas`, contendo os DTOs de entrada e saída. 
Cada DTO possui métodos de validação para barrar dados inconsistentes 
antes que atinjam a camada de banco de dados.

```pascal
unit DTOs.OrdemServico;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, fpjson, jsonparser, Core.Exceptions;

type
  { DTO para item de ordem de servico na entrada }
  TItemOSInputDTO = class
  private
    FDescricao: string;
    FQuantidade: Double;
    FValorUnitario: Double;
  public
    procedure Validar;
    property Descricao: string read FDescricao write FDescricao;
    property Quantidade: Double read FQuantidade write FQuantidade;
    property ValorUnitario: Double 
      read FValorUnitario write FValorUnitario;
  end;

  { DTO para criacao da ordem de servico }
  TOrdemServicoInputDTO = class
  private
    FClienteId: Int64;
    FDescricaoProblema: string;
    FObservacoes: string;
    FItens: TList;
    function GetItem(AIndex: Integer): TItemOSInputDTO;
    function GetTotalItens: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AdicionarItem(AItem: TItemOSInputDTO);
    procedure Validar;
    class function FromJSON(const AJSONStr: string): 
      TOrdemServicoInputDTO; static;
    property ClienteId: Int64 read FClienteId write FClienteId;
    property DescricaoProblema: string 
      read FDescricaoProblema write FDescricaoProblema;
    property Observacoes: string 
      read FObservacoes write FObservacoes;
    property Itens[AIndex: Integer]: TItemOSInputDTO read GetItem;
    property TotalItens: Integer read GetTotalItens;
  end;

  { DTO para retorno da OS detalhada }
  TOrdemServicoOutputDTO = class
  private
    FId: Int64;
    FTenantId: Int64;
    FClienteId: Int64;
    FNomeCliente: string;
    FStatus: string;
    FDescricaoProblema: string;
    FValorTotal: Double;
    FCriadoEm: string;
    FItensJSON: TJSONArray;
  public
    constructor Create;
    destructor Destroy; override;
    function ToJSONObject: TJSONObject;
    property Id: Int64 read FId write FId;
    property TenantId: Int64 read FTenantId write FTenantId;
    property ClienteId: Int64 read FClienteId write FClienteId;
    property NomeCliente: string read FNomeCliente write FNomeCliente;
    property Status: string read FStatus write FStatus;
    property DescricaoProblema: string 
      read FDescricaoProblema write FDescricaoProblema;
    property ValorTotal: Double read FValorTotal write FValorTotal;
    property CriadoEm: string read FCriadoEm write FCriadoEm;
    property ItensJSON: TJSONArray read FItensJSON write FItensJSON;
  end;

implementation

{ TItemOSInputDTO }

procedure TItemOSInputDTO.Validar;
begin
  if Trim(FDescricao) = '' then
    raise EValidationException.Create(
      'Descricao do item da OS e obrigatoria');
  if FQuantidade <= 0 then
    raise EValidationException.Create(
      'Quantidade do item deve ser maior que zero');
  if FValorUnitario < 0 then
    raise EValidationException.Create(
      'Valor unitario nao pode ser negativo');
end;

{ TOrdemServicoInputDTO }

constructor TOrdemServicoInputDTO.Create;
begin
  inherited Create;
  FItens := TList.Create;
end;

destructor TOrdemServicoInputDTO.Destroy;
var
  i: Integer;
begin
  for i := 0 to FItens.Count - 1 do
    TItemOSInputDTO(FItens[i]).Free;
  FItens.Free;
  inherited Destroy;
end;

procedure TOrdemServicoInputDTO.AdicionarItem(AItem: TItemOSInputDTO);
begin
  FItens.Add(AItem);
end;

function TOrdemServicoInputDTO.GetItem(
  AIndex: Integer): TItemOSInputDTO;
begin
  Result := TItemOSInputDTO(FItens[AIndex]);
end;

function TOrdemServicoInputDTO.GetTotalItens: Integer;
begin
  Result := FItens.Count;
end;

procedure TOrdemServicoInputDTO.Validar;
var
  i: Integer;
begin
  if FClienteId <= 0 then
    raise EValidationException.Create('Cliente ID invalido ou ausente');
  if Trim(FDescricaoProblema) = '' then
    raise EValidationException.Create(
      'Descricao do problema e obrigatoria');
  if FItens.Count = 0 then
    raise EValidationException.Create(
      'A Ordem de Servico deve possuir ao menos 1 item');

  for i := 0 to FItens.Count - 1 do
    TItemOSInputDTO(FItens[i]).Validar;
end;

class function TOrdemServicoInputDTO.FromJSON(
  const AJSONStr: string): TOrdemServicoInputDTO;
var
  vData: TJSONData;
  vObj, vItemObj: TJSONObject;
  vArr: TJSONArray;
  vItem: TItemOSInputDTO;
  i: Integer;
begin
  vData := GetJSON(AJSONStr);
  try
    if not (vData is TJSONObject) then
      raise EValidationException.Create('Payload deve ser objeto JSON');
    vObj := TJSONObject(vData);

    Result := TOrdemServicoInputDTO.Create;
    try
      Result.ClienteId := vObj.Get('cliente_id', Int64(0));
      Result.DescricaoProblema := vObj.Get('descricao_problema', '');
      Result.Observacoes := vObj.Get('observacoes', '');

      vArr := vObj.FindPath('itens') as TJSONArray;
      if Assigned(vArr) then
      begin
        for i := 0 to vArr.Count - 1 do
        begin
          if vArr.Types[i] = jtObject then
          begin
            vItemObj := vArr.Objects[i];
            vItem := TItemOSInputDTO.Create;
            vItem.Descricao := vItemObj.Get('descricao', '');
            vItem.Quantidade := vItemObj.Get('quantidade', 0.0);
            vItem.ValorUnitario := vItemObj.Get('valor_unitario', 0.0);
            Result.AdicionarItem(vItem);
          end;
        end;
      end;
      Result.Validar;
    except
      Result.Free;
      raise;
    end;
  finally
    vData.Free;
  end;
end;

{ TOrdemServicoOutputDTO }

constructor TOrdemServicoOutputDTO.Create;
begin
  inherited Create;
  FItensJSON := TJSONArray.Create;
end;

destructor TOrdemServicoOutputDTO.Destroy;
begin
  FItensJSON.Free;
  inherited Destroy;
end;

function TOrdemServicoOutputDTO.ToJSONObject: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('id', FId);
  Result.Add('tenant_id', FTenantId);
  Result.Add('cliente_id', FClienteId);
  Result.Add('nome_cliente', FNomeCliente);
  Result.Add('status', FStatus);
  Result.Add('descricao_problema', FDescricaoProblema);
  Result.Add('valor_total', FValorTotal);
  Result.Add('criado_em', FCriadoEm);
  { Clone do array de itens para serializacao independente }
  Result.Add('itens', FItensJSON.Clone as TJSONArray);
end;

end.
```

### 3.2 O Contrato do Unit of Work e Interfaces de Repositório

Definiremos as interfaces em `Interfaces.OrdemServico.pas`. O contrato 
`IUnitOfWork` gerencia o escopo da transação, enquanto os repositórios 
operam sobre a conexão compartilhada:

```pascal
unit Interfaces.OrdemServico;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Core.ConnectionPool, DTOs.OrdemServico;

type
  { Contrato para o Unit of Work }
  IUnitOfWork = interface
    ['{8A9B1C2D-3E4F-5A6B-7C8D-9E0F1A2B3C4D}']
    procedure BeginTransaction;
    procedure Commit;
    procedure Rollback;
    function Wrapper: IConnectionWrapper;
  end;

  { Repositorio de Ordens de Servico }
  IOrdemServicoRepository = interface
    ['{1F2E3D4C-5B6A-7980-A1B2-C3D4E5F6A7B8}']
    function InserirCabecalho(const ATenantId: Int64; 
      ADTO: TOrdemServicoInputDTO; const AValorTotal: Double): Int64;
    procedure InserirItem(const ATenantId, AOSId: Int64; 
      AItem: TItemOSInputDTO);
    function ObterPorId(const ATenantId, AOSId: Int64): 
      TOrdemServicoOutputDTO;
    procedure AtualizarStatus(const ATenantId, AOSId: Int64; 
      const ANovoStatus: string);
    procedure Excluir(const ATenantId, AOSId: Int64);
  end;

  { Service de Dominio para regras de negocio de OS }
  IOrdemServicoService = interface
    ['{2A3B4C5D-6E7F-8091-A2B3-C4D5E6F7A8B9}']
    function CriarOS(const ATenantId: Int64; 
      ADTO: TOrdemServicoInputDTO): TOrdemServicoOutputDTO;
    function BuscarPorId(const ATenantId, AOSId: Int64): 
      TOrdemServicoOutputDTO;
    procedure MudarStatus(const ATenantId, AOSId: Int64; 
      const ANovoStatus: string);
    procedure CancelarOS(const ATenantId, AOSId: Int64);
  end;

implementation

end.
```

### 3.3 Implementando o Unit of Work e Repositório Firebird 5.0

Na unit `Repositories.OrdemServico.pas`, estruturamos a persistência 
atômica. Observe o aproveitamento da cláusula `RETURNING id` do 
Firebird 5.0:

```pascal
unit Repositories.OrdemServico;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, sqldb, IBConnection, fpjson,
  Core.ConnectionPool, Core.Exceptions, DTOs.OrdemServico,
  Interfaces.OrdemServico;

type
  { Implementacao concreta do Unit of Work }
  TUnitOfWork = class(TInterfacedObject, IUnitOfWork)
  private
    FWrapper: IConnectionWrapper;
  public
    constructor Create;
    procedure BeginTransaction;
    procedure Commit;
    procedure Rollback;
    function Wrapper: IConnectionWrapper;
  end;

  { Implementacao concreta do repositorio de OS }
  TOrdemServicoRepository = class(TInterfacedObject, 
    IOrdemServicoRepository)
  private
    FUoW: IUnitOfWork;
  public
    constructor Create(AUoW: IUnitOfWork);
    function InserirCabecalho(const ATenantId: Int64; 
      ADTO: TOrdemServicoInputDTO; const AValorTotal: Double): Int64;
    procedure InserirItem(const ATenantId, AOSId: Int64; 
      AItem: TItemOSInputDTO);
    function ObterPorId(const ATenantId, AOSId: Int64): 
      TOrdemServicoOutputDTO;
    procedure AtualizarStatus(const ATenantId, AOSId: Int64; 
      const ANovoStatus: string);
    procedure Excluir(const ATenantId, AOSId: Int64);
  end;

implementation

{ TUnitOfWork }

constructor TUnitOfWork.Create;
begin
  inherited Create;
  FWrapper := TFirebirdConnectionPool.Instance.Acquire;
end;

procedure TUnitOfWork.BeginTransaction;
begin
  if not FWrapper.Transaction.Active then
    FWrapper.Transaction.StartTransaction;
end;

procedure TUnitOfWork.Commit;
begin
  if FWrapper.Transaction.Active then
    FWrapper.Transaction.Commit;
end;

procedure TUnitOfWork.Rollback;
begin
  if FWrapper.Transaction.Active then
    FWrapper.Transaction.Rollback;
end;

function TUnitOfWork.Wrapper: IConnectionWrapper;
begin
  Result := FWrapper;
end;

{ TOrdemServicoRepository }

constructor TOrdemServicoRepository.Create(AUoW: IUnitOfWork);
begin
  inherited Create;
  FUoW := AUoW;
end;

function TOrdemServicoRepository.InserirCabecalho(
  const ATenantId: Int64; ADTO: TOrdemServicoInputDTO; 
  const AValorTotal: Double): Int64;
var
  vQry: TSQLQuery;
begin
  vQry := TSQLQuery.Create(nil);
  try
    vQry.DataBase := FUoW.Wrapper.Connection;
    vQry.Transaction := FUoW.Wrapper.Transaction;
    vQry.SQL.Text := 
      'INSERT INTO ordens_servico (' +
      '  tenant_id, cliente_id, status, descricao_problema, ' +
      '  observacoes, valor_total, criado_em' +
      ') VALUES (' +
      '  :tenant_id, :cliente_id, ''ABERTA'', :problema, ' +
      '  :obs, :total, CURRENT_TIMESTAMP' +
      ') RETURNING id';

    vQry.ParamByName('tenant_id').AsLargeInt := ATenantId;
    vQry.ParamByName('cliente_id').AsLargeInt := ADTO.ClienteId;
    vQry.ParamByName('problema').AsString := ADTO.DescricaoProblema;
    vQry.ParamByName('obs').AsString := ADTO.Observacoes;
    vQry.ParamByName('total').AsFloat := AValorTotal;
    vQry.Open;

    if not vQry.EOF then
      Result := vQry.FieldByName('id').AsLargeInt
    else
      raise EDatabaseException.Create(
        'Falha ao obter ID gerado para Ordem de Servico');
  finally
    vQry.Free;
  end;
end;

procedure TOrdemServicoRepository.InserirItem(const ATenantId, 
  AOSId: Int64; AItem: TItemOSInputDTO);
var
  vQry: TSQLQuery;
  vSubtotal: Double;
begin
  vQry := TSQLQuery.Create(nil);
  try
    vQry.DataBase := FUoW.Wrapper.Connection;
    vQry.Transaction := FUoW.Wrapper.Transaction;
    vSubtotal := AItem.Quantidade * AItem.ValorUnitario;

    vQry.SQL.Text := 
      'INSERT INTO itens_ordem_servico (' +
      '  tenant_id, ordem_servico_id, descricao, quantidade, ' +
      '  valor_unitario, subtotal' +
      ') VALUES (' +
      '  :tenant_id, :os_id, :descricao, :qtd, :vl_unit, :subtotal' +
      ')';

    vQry.ParamByName('tenant_id').AsLargeInt := ATenantId;
    vQry.ParamByName('os_id').AsLargeInt := AOSId;
    vQry.ParamByName('descricao').AsString := AItem.Descricao;
    vQry.ParamByName('qtd').AsFloat := AItem.Quantidade;
    vQry.ParamByName('vl_unit').AsFloat := AItem.ValorUnitario;
    vQry.ParamByName('subtotal').AsFloat := vSubtotal;
    vQry.ExecSQL;
  finally
    vQry.Free;
  end;
end;

function TOrdemServicoRepository.ObterPorId(const ATenantId, 
  AOSId: Int64): TOrdemServicoOutputDTO;
var
  vQry, vQryItens: TSQLQuery;
  vItemObj: TJSONObject;
begin
  Result := nil;
  vQry := TSQLQuery.Create(nil);
  try
    vQry.DataBase := FUoW.Wrapper.Connection;
    vQry.Transaction := FUoW.Wrapper.Transaction;
    vQry.SQL.Text := 
      'SELECT o.id, o.tenant_id, o.cliente_id, ' +
      '       c.nome AS nome_cliente, ' +
      '       o.status, o.descricao_problema, o.valor_total, ' +
      '       CAST(o.criado_em AS VARCHAR(25)) AS criado_em ' +
      'FROM ordens_servico o ' +
      'INNER JOIN clientes c ON (c.id = o.cliente_id AND ' +
      '                          c.tenant_id = o.tenant_id) ' +
      'WHERE o.tenant_id = :tenant_id AND o.id = :id';

    vQry.ParamByName('tenant_id').AsLargeInt := ATenantId;
    vQry.ParamByName('id').AsLargeInt := AOSId;
    vQry.Open;

    if vQry.EOF then
      Exit;

    Result := TOrdemServicoOutputDTO.Create;
    Result.Id := vQry.FieldByName('id').AsLargeInt;
    Result.TenantId := vQry.FieldByName('tenant_id').AsLargeInt;
    Result.ClienteId := vQry.FieldByName('cliente_id').AsLargeInt;
    Result.NomeCliente := vQry.FieldByName('nome_cliente').AsString;
    Result.Status := vQry.FieldByName('status').AsString;
    Result.DescricaoProblema := 
      vQry.FieldByName('descricao_problema').AsString;
    Result.ValorTotal := vQry.FieldByName('valor_total').AsFloat;
    Result.CriadoEm := vQry.FieldByName('criado_em').AsString;

    { Carrega itens da OS }
    vQryItens := TSQLQuery.Create(nil);
    try
      vQryItens.DataBase := FUoW.Wrapper.Connection;
      vQryItens.Transaction := FUoW.Wrapper.Transaction;
      vQryItens.SQL.Text := 
        'SELECT id, descricao, quantidade, valor_unitario, subtotal ' +
        'FROM itens_ordem_servico ' +
        'WHERE tenant_id = :tenant_id AND ordem_servico_id = :os_id ' +
        'ORDER BY id';
      vQryItens.ParamByName('tenant_id').AsLargeInt := ATenantId;
      vQryItens.ParamByName('os_id').AsLargeInt := AOSId;
      vQryItens.Open;

      while not vQryItens.EOF do
      begin
        vItemObj := TJSONObject.Create;
        vItemObj.Add('id', vQryItens.FieldByName('id').AsLargeInt);
        vItemObj.Add('descricao', 
          vQryItens.FieldByName('descricao').AsString);
        vItemObj.Add('quantidade', 
          vQryItens.FieldByName('quantidade').AsFloat);
        vItemObj.Add('valor_unitario', 
          vQryItens.FieldByName('valor_unitario').AsFloat);
        vItemObj.Add('subtotal', 
          vQryItens.FieldByName('subtotal').AsFloat);
        Result.ItensJSON.Add(vItemObj);
        vQryItens.Next;
      end;
    finally
      vQryItens.Free;
    end;
  finally
    vQry.Free;
  end;
end;

procedure TOrdemServicoRepository.AtualizarStatus(const ATenantId, 
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

procedure TOrdemServicoRepository.Excluir(const ATenantId, 
  AOSId: Int64);
var
  vQry: TSQLQuery;
begin
  vQry := TSQLQuery.Create(nil);
  try
    vQry.DataBase := FUoW.Wrapper.Connection;
    vQry.Transaction := FUoW.Wrapper.Transaction;
    { Exclui itens primeiro (ou via CASCADE no banco) }
    vQry.SQL.Text := 
      'DELETE FROM itens_ordem_servico ' +
      'WHERE tenant_id = :tenant_id AND ordem_servico_id = :os_id';
    vQry.ParamByName('tenant_id').AsLargeInt := ATenantId;
    vQry.ParamByName('os_id').AsLargeInt := AOSId;
    vQry.ExecSQL;

    { Exclui cabecalho }
    vQry.SQL.Text := 
      'DELETE FROM ordens_servico ' +
      'WHERE tenant_id = :tenant_id AND id = :id';
    vQry.ParamByName('tenant_id').AsLargeInt := ATenantId;
    vQry.ParamByName('id').AsLargeInt := AOSId;
    vQry.ExecSQL;
  finally
    vQry.Free;
  end;
end;

end.
```

### 3.4 Service de Domínio: Regras de Negócio e Máquina de Estados

Na camada de serviço (`Services.OrdemServico.pas`), centralizamos a 
máquina de transição de estados e garantimos que todo o processo de 
gravação de mestre e detalhes ocorra em bloco atômico:

```pascal
unit Services.OrdemServico;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Core.Exceptions, DTOs.OrdemServico,
  Interfaces.OrdemServico, Repositories.OrdemServico;

type
  { Implementacao de regras de negocio da OS }
  TOrdemServicoService = class(TInterfacedObject, IOrdemServicoService)
  private
    function CalcularTotal(ADTO: TOrdemServicoInputDTO): Double;
    procedure ValidarTransicaoStatus(const AStatusAtual, 
      ANovoStatus: string);
  public
    function CriarOS(const ATenantId: Int64; 
      ADTO: TOrdemServicoInputDTO): TOrdemServicoOutputDTO;
    function BuscarPorId(const ATenantId, AOSId: Int64): 
      TOrdemServicoOutputDTO;
    procedure MudarStatus(const ATenantId, AOSId: Int64; 
      const ANovoStatus: string);
    procedure CancelarOS(const ATenantId, AOSId: Int64);
  end;

implementation

function TOrdemServicoService.CalcularTotal(
  ADTO: TOrdemServicoInputDTO): Double;
var
  i: Integer;
begin
  Result := 0.0;
  for i := 0 to ADTO.TotalItens - 1 do
    Result := Result + (ADTO.Itens[i].Quantidade * 
      ADTO.Itens[i].ValorUnitario);
end;

procedure TOrdemServicoService.ValidarTransicaoStatus(
  const AStatusAtual, ANovoStatus: string);
begin
  if AStatusAtual = ANovoStatus then Exit;

  if (AStatusAtual = 'CONCLUIDA') or (AStatusAtual = 'CANCELADA') then
    raise EBusinessException.Create(
      'Ordem de Servico finalizada nao permite alteracao de status');

  if (AStatusAtual = 'ABERTA') and (ANovoStatus <> 'EM_EXECUCAO') and 
     (ANovoStatus <> 'CANCELADA') then
    raise EBusinessException.Create(
      'OS Aberta so transiciona para EM_EXECUCAO ou CANCELADA');

  if (AStatusAtual = 'EM_EXECUCAO') and 
     (ANovoStatus <> 'CONCLUIDA') and (ANovoStatus <> 'CANCELADA') then
    raise EBusinessException.Create(
      'OS Em Execucao so transiciona para CONCLUIDA ou CANCELADA');
end;

function TOrdemServicoService.CriarOS(const ATenantId: Int64; 
  ADTO: TOrdemServicoInputDTO): TOrdemServicoOutputDTO;
var
  vUoW: IUnitOfWork;
  vRepo: IOrdemServicoRepository;
  vTotal: Double;
  vNovoId: Int64;
  i: Integer;
begin
  ADTO.Validar;
  vTotal := CalcularTotal(ADTO);

  vUoW := TUnitOfWork.Create;
  vRepo := TOrdemServicoRepository.Create(vUoW);

  vUoW.BeginTransaction;
  try
    vNovoId := vRepo.InserirCabecalho(ATenantId, ADTO, vTotal);
    for i := 0 to ADTO.TotalItens - 1 do
      vRepo.InserirItem(ATenantId, vNovoId, ADTO.Itens[i]);

    vUoW.Commit;
  except
    vUoW.Rollback;
    raise;
  end;

  Result := vRepo.ObterPorId(ATenantId, vNovoId);
end;

function TOrdemServicoService.BuscarPorId(const ATenantId, 
  AOSId: Int64): TOrdemServicoOutputDTO;
var
  vUoW: IUnitOfWork;
  vRepo: IOrdemServicoRepository;
begin
  vUoW := TUnitOfWork.Create;
  vRepo := TOrdemServicoRepository.Create(vUoW);
  Result := vRepo.ObterPorId(ATenantId, AOSId);
  if not Assigned(Result) then
    raise ENotFoundException.Create(
      Format('Ordem de Servico %d nao encontrada', [AOSId]));
end;

procedure TOrdemServicoService.MudarStatus(const ATenantId, 
  AOSId: Int64; const ANovoStatus: string);
var
  vUoW: IUnitOfWork;
  vRepo: IOrdemServicoRepository;
  vOS: TOrdemServicoOutputDTO;
  vStatusUpper: string;
begin
  vStatusUpper := UpperCase(Trim(ANovoStatus));
  vUoW := TUnitOfWork.Create;
  vRepo := TOrdemServicoRepository.Create(vUoW);

  vOS := vRepo.ObterPorId(ATenantId, AOSId);
  if not Assigned(vOS) then
    raise ENotFoundException.Create(
      Format('Ordem de Servico %d nao encontrada', [AOSId]));
  try
    ValidarTransicaoStatus(vOS.Status, vStatusUpper);
    vUoW.BeginTransaction;
    try
      vRepo.AtualizarStatus(ATenantId, AOSId, vStatusUpper);
      vUoW.Commit;
    except
      vUoW.Rollback;
      raise;
    end;
  finally
    vOS.Free;
  end;
end;

procedure TOrdemServicoService.CancelarOS(const ATenantId, 
  AOSId: Int64);
begin
  MudarStatus(ATenantId, AOSId, 'CANCELADA');
end;

end.
```

### 3.5 Controller HTTP Horse

Finalizamos a implementação conectando a rota REST no Horse 
(`Controllers.OrdemServico.pas`):

```pascal
unit Controllers.OrdemServico;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, fpjson, Horse, Core.Exceptions,
  DTOs.OrdemServico, Interfaces.OrdemServico, Services.OrdemServico;

type
  TOrdemServicoController = class
  public
    class procedure RegistrarRotas;
    class procedure Criar(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
    class procedure ObterPorId(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
    class procedure AlterarStatus(Req: THorseRequest; 
      Res: THorseResponse; Next: TNextProc);
    class procedure Cancelar(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
  end;

implementation

class procedure TOrdemServicoController.RegistrarRotas;
begin
  THorse.Group('/api/v1/ordens-servico')
    .Post('/', @Criar)
    .Get('/:id', @ObterPorId)
    .Patch('/:id/status', @AlterarStatus)
    .Delete('/:id', @Cancelar);
end;

class procedure TOrdemServicoController.Criar(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vTenantId: Int64;
  vDTO: TOrdemServicoInputDTO;
  vOutput: TOrdemServicoOutputDTO;
  vService: IOrdemServicoService;
  vJSON: TJSONObject;
begin
  vTenantId := Req.Session<Int64>('tenant_id');
  if vTenantId <= 0 then
    vTenantId := 1; { Fallback para tenant padrao em dev }

  vDTO := TOrdemServicoInputDTO.FromJSON(Req.Body);
  try
    vService := TOrdemServicoService.Create;
    vOutput := vService.CriarOS(vTenantId, vDTO);
    try
      vJSON := vOutput.ToJSONObject;
      Res.Status(201).Send<TJSONObject>(vJSON);
    finally
      vOutput.Free;
    end;
  finally
    vDTO.Free;
  end;
end;

class procedure TOrdemServicoController.ObterPorId(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vTenantId, vId: Int64;
  vService: IOrdemServicoService;
  vOutput: TOrdemServicoOutputDTO;
begin
  vTenantId := Req.Session<Int64>('tenant_id');
  if vTenantId <= 0 then vTenantId := 1;
  vId := StrToInt64Def(Req.Params['id'], 0);

  vService := TOrdemServicoService.Create;
  vOutput := vService.BuscarPorId(vTenantId, vId);
  try
    Res.Status(200).Send<TJSONObject>(vOutput.ToJSONObject);
  finally
    vOutput.Free;
  end;
end;

class procedure TOrdemServicoController.AlterarStatus(
  Req: THorseRequest; Res: THorseResponse; Next: TNextProc);
var
  vTenantId, vId: Int64;
  vService: IOrdemServicoService;
  vBody: TJSONData;
  vNovoStatus: string;
begin
  vTenantId := Req.Session<Int64>('tenant_id');
  if vTenantId <= 0 then vTenantId := 1;
  vId := StrToInt64Def(Req.Params['id'], 0);

  vBody := GetJSON(Req.Body);
  try
    vNovoStatus := TJSONObject(vBody).Get('status', '');
  finally
    vBody.Free;
  end;

  vService := TOrdemServicoService.Create;
  vService.MudarStatus(vTenantId, vId, vNovoStatus);
  Res.Status(204).Send('');
end;

class procedure TOrdemServicoController.Cancelar(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vTenantId, vId: Int64;
  vService: IOrdemServicoService;
begin
  vTenantId := Req.Session<Int64>('tenant_id');
  if vTenantId <= 0 then vTenantId := 1;
  vId := StrToInt64Def(Req.Params['id'], 0);

  vService := TOrdemServicoService.Create;
  vService.CancelarOS(vTenantId, vId);
  Res.Status(204).Send('');
end;

end.
```

---

## 4. Testando o Endpoint

Abaixo estão os testes com `curl` para validação em produção.

### 4.1 Criando uma Ordem de Serviço com Itens (POST)

```bash
curl -i -X POST http://localhost:9000/api/v1/ordens-servico \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <SEU_JWT_AQUI>" \
  -d '{
    "cliente_id": 1,
    "descricao_problema": "Servidor desliga apos 10 minutos de carga",
    "observacoes": "Equipamento em garantia contratual",
    "itens": [
      {
        "descricao": "Diagnostico termico e troca de pasta termica",
        "quantidade": 1.0,
        "valor_unitario": 250.00
      },
      {
        "descricao": "Cooler fan de alta pressao 120mm",
        "quantidade": 2.0,
        "valor_unitario": 85.00
      }
    ]
  }'
```

**Resposta esperada (`201 Created`):**
```json
{
  "id": 1,
  "tenant_id": 1,
  "cliente_id": 1,
  "nome_cliente": "Industrias ACME Ltda",
  "status": "ABERTA",
  "descricao_problema": "Servidor desliga apos 10 minutos de carga",
  "valor_total": 420.0,
  "criado_em": "2026-11-23 09:30:00",
  "itens": [
    {
      "id": 1,
      "descricao": "Diagnostico termico e troca de pasta termica",
      "quantidade": 1.0,
      "valor_unitario": 250.0,
      "subtotal": 250.0
    },
    {
      "id": 2,
      "descricao": "Cooler fan de alta pressao 120mm",
      "quantidade": 2.0,
      "valor_unitario": 85.0,
      "subtotal": 170.0
    }
  ]
}
```

### 4.2 Consultando a Ordem de Serviço por ID (GET)

```bash
curl -i -X GET http://localhost:9000/api/v1/ordens-servico/1 \
  -H "Authorization: Bearer <SEU_JWT_AQUI>"
```

### 4.3 Tentativa de Transição Inválida de Status (PATCH)

Tentando finalizar diretamente uma OS que ainda está `ABERTA`:

```bash
curl -i -X PATCH http://localhost:9000/api/v1/ordens-servico/1/status \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <SEU_JWT_AQUI>" \
  -d '{"status": "CONCLUIDA"}'
```

**Resposta de Erro (`422 Unprocessable Entity` via RFC 7807):**
```json
{
  "type": "https://api.connectos.com.br/errors/business-rule",
  "title": "Violacao de Regra de Negocio",
  "status": 422,
  "detail": "OS Aberta so transiciona para EM_EXECUCAO ou CANCELADA",
  "instance": "/api/v1/ordens-servico/1/status"
}
```

### 4.4 Cancelando uma Ordem de Serviço (DELETE)

```bash
curl -i -X DELETE http://localhost:9000/api/v1/ordens-servico/1 \
  -H "Authorization: Bearer <SEU_JWT_AQUI>"
```

**Resposta esperada:** `204 No Content`.

---

## 5. Armadilhas Comuns e Troubleshooting no FPC/Lazarus

### 5.1 O Erro Fatal de Abrir Query com Transação Inativa
No `SQLdb`, ao invocar `vQry.Open` ou `vQry.ExecSQL` sem que 
`Transaction.StartTransaction` tenha sido chamado previamente, o FPC 
inicia a transação implicitamente. Contudo, se a transação for implícita, 
muitos programadores esquecem de chamar `Commit`, deixando cursores 
abertos na `fbclient`. 

**Regra de ouro:** Sempre controle a abertura explicitamente através do 
`IUnitOfWork.BeginTransaction`.

### 5.2 Não Limpar Cursores de `TSQLQuery` Antes do `Commit`
Se um `TSQLQuery` permanecer aberto no momento em que `Transaction.Commit` 
for executado, a `fbclient` fecha o cursor abruptamente ou pode disparar 
a exceção `Transaction is active`. 

**Solução:** Garanta que todas as instâncias de `TSQLQuery` criadas na 
rotina sejam destruídas (`vQry.Free`) antes do fechamento formal da 
transação no Unit of Work.

### 5.3 Conflito de Concorrência com Deadlock
Se duas requisições concorrentes tentarem atualizar simultaneamente a 
mesma linha com a transação configurada em `NOWAIT`, o Firebird 5.0 
lança imediatamente o erro de código `isc_deadlock` ou `isc_lock_conflict`. 
Para mitigar isso:
1. Mantenha as transações de escrita o mais curtas possível.
2. Execute todos os cálculos e validações em memória antes de disparar 
   o `BeginTransaction`.
3. Ordene a inserção de itens de forma determinística (por exemplo, 
   ordenando por `produto_id` ou índice crescente) para evitar bloqueios 
   cruzados.

---

## 6. Resumo Executivo e Checklist de Revisão

Neste módulo, implementamos o fluxo completo de uma entidade agregada 
mestre-detalhe (Ordem de Serviço e seus Itens), garantindo consistência 
relacional e isolamento transacional estrito no Firebird 5.0.

### Checklist de Revisão
- [ ] O Unit of Work gerencia um `IConnectionWrapper` obtido do Pool e 
      garante que `Commit` e `Rollback` sejam chamados no bloco `try..finally`?
- [ ] O código utiliza `Commit` puro e não `CommitRetaining`, preservando o 
      avanço da OAT e a coleta de lixo no Firebird?
- [ ] A inserção do cabeçalho da OS utiliza `RETURNING id` nativo do 
      Firebird 5.0, eliminando queries adicionais de `GEN_ID`?
- [ ] Os DTOs de entrada realizam validações estritas de dados antes de 
      qualquer interação com o banco de dados?
- [ ] A máquina de estados da OS valida rigorosamente as transições de status 
      permitidas, impedindo alterações ilegais?
- [ ] Todas as consultas e operações filtram explicitamente por `tenant_id`, 
      assegurando isolamento multi-tenant completo?
