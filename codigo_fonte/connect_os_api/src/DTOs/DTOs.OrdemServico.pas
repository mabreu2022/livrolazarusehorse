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

function TOrdemServicoInputDTO.GetItem(AIndex: Integer): TItemOSInputDTO;
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
  Result.Add('itens', FItensJSON.Clone as TJSONArray);
end;

end.
