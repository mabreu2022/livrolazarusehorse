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
    class procedure AlterarStatus(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
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
    vTenantId := 1;

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

class procedure TOrdemServicoController.AlterarStatus(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
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
