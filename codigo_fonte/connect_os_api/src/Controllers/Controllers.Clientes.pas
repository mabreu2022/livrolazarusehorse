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
