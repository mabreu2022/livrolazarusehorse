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
      'SELECT o.id, o.tenant_id, o.cliente_id, c.nome AS nome_cliente, ' +
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
    vQry.SQL.Text := 
      'DELETE FROM itens_ordem_servico ' +
      'WHERE tenant_id = :tenant_id AND ordem_servico_id = :os_id';
    vQry.ParamByName('tenant_id').AsLargeInt := ATenantId;
    vQry.ParamByName('os_id').AsLargeInt := AOSId;
    vQry.ExecSQL;

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
