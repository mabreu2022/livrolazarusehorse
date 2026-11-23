unit DTOs.Cliente;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  fpjson,
  jsonparser;

type
  TClienteDTO = class
  private
    FId: Int64;
    FNomeRazao: string;
    FCPFCNPJ: string;
    FEmail: string;
    FTelefone: string;
    FAtivo: Boolean;
  public
    property Id: Int64 read FId write FId;
    property NomeRazao: string read FNomeRazao write FNomeRazao;
    property CPFCNPJ: string read FCPFCNPJ write FCPFCNPJ;
    property Email: string read FEmail write FEmail;
    property Telefone: string read FTelefone write FTelefone;
    property Ativo: Boolean read FAtivo write FAtivo;

    function ToJSONObject: TJSONObject;
    class function FromJSONObject(AJSON: TJSONObject): TClienteDTO;
  end;

  TClienteInputDTO = class
  private
    FNomeRazao: string;
    FCPFCNPJ: string;
    FEmail: string;
    FTelefone: string;
  public
    property NomeRazao: string read FNomeRazao write FNomeRazao;
    property CPFCNPJ: string read FCPFCNPJ write FCPFCNPJ;
    property Email: string read FEmail write FEmail;
    property Telefone: string read FTelefone write FTelefone;

    class function FromJSONString(const AJSONStr: string): 
      TClienteInputDTO;
    class function FromJSONObject(AJSON: TJSONObject): 
      TClienteInputDTO;
  end;

implementation

{ TClienteDTO }

function TClienteDTO.ToJSONObject: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('id', FId);
  Result.Add('nome_razao', FNomeRazao);
  Result.Add('cpf_cnpj', FCPFCNPJ);
  Result.Add('email', FEmail);
  Result.Add('telefone', FTelefone);
  Result.Add('ativo', FAtivo);
end;

class function TClienteDTO.FromJSONObject(AJSON: TJSONObject): 
  TClienteDTO;
begin
  Result := TClienteDTO.Create;
  if not Assigned(AJSON) then
    Exit;

  Result.FId := AJSON.Get('id', Int64(0));
  Result.FNomeRazao := AJSON.Get('nome_razao', '');
  Result.FCPFCNPJ := AJSON.Get('cpf_cnpj', '');
  Result.FEmail := AJSON.Get('email', '');
  Result.FTelefone := AJSON.Get('telefone', '');
  Result.FAtivo := AJSON.Get('ativo', True);
end;

{ TClienteInputDTO }

class function TClienteInputDTO.FromJSONObject(AJSON: TJSONObject): 
  TClienteInputDTO;
begin
  Result := TClienteInputDTO.Create;
  if not Assigned(AJSON) then
    Exit;

  Result.FNomeRazao := Trim(AJSON.Get('nome_razao', ''));
  Result.FCPFCNPJ := Trim(AJSON.Get('cpf_cnpj', ''));
  Result.FEmail := Trim(AJSON.Get('email', ''));
  Result.FTelefone := Trim(AJSON.Get('telefone', ''));
end;

class function TClienteInputDTO.FromJSONString(
  const AJSONStr: string): TClienteInputDTO;
var
  vParser: TJSONParser;
  vJSONData: TJSONData;
begin
  Result := nil;
  if Trim(AJSONStr) = '' then
    Exit;

  vParser := TJSONParser.Create(AJSONStr, [joUTF8]);
  try
    try
      vJSONData := vParser.Parse;
      if Assigned(vJSONData) and (vJSONData is TJSONObject) then
      begin
        Result := FromJSONObject(TJSONObject(vJSONData));
        vJSONData.Free;
      end;
    except
      Result := nil;
    end;
  finally
    vParser.Free;
  end;
end;

end.
