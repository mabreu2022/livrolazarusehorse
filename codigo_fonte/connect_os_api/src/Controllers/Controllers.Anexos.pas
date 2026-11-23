unit Controllers.Anexos;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, fpjson, Horse, Horse.OctetStream,
  Core.Exceptions, DTOs.Anexo, Services.Anexo;

type
  TAnexosController = class
  public
    class procedure RegistrarRotas;
    class procedure UploadAnexo(Req: THorseRequest; 
      Res: THorseResponse; Next: TNextProc);
    class procedure DownloadAnexo(Req: THorseRequest; 
      Res: THorseResponse; Next: TNextProc);
  end;

implementation

class procedure TAnexosController.RegistrarRotas;
begin
  THorse.Group('/api/v1/ordens-servico/:id/anexos')
    .Post('/', @UploadAnexo)
    .Get('/:anexo_id/download', @DownloadAnexo);
end;

class procedure TAnexosController.UploadAnexo(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vTenantId, vOSId: Int64;
  vNomeOriginal, vMimeType: string;
  vStream: TMemoryStream;
  vService: TAnexoService;
  vOutput: TAnexoOutputDTO;
begin
  vTenantId := Req.Session<Int64>('tenant_id');
  if vTenantId <= 0 then vTenantId := 1;
  vOSId := StrToInt64Def(Req.Params['id'], 0);

  vNomeOriginal := Req.Headers['X-File-Name'];
  if vNomeOriginal = '' then
    vNomeOriginal := 'upload_' + FormatDateTime('hhnnss', Now) + '.bin';

  vMimeType := Req.Headers['Content-Type'];
  if vMimeType = '' then
    vMimeType := 'application/octet-stream';

  vStream := TMemoryStream.Create;
  try
    if Req.Body <> '' then
      vStream.WriteBuffer(Pointer(Req.Body)^, Length(Req.Body));

    vService := TAnexoService.Create;
    try
      vOutput := vService.SalvarUpload(vTenantId, vOSId, vNomeOriginal, 
        vMimeType, vStream);
      try
        Res.Status(201).Send<TJSONObject>(vOutput.ToJSONObject);
      finally
        vOutput.Free;
      end;
    finally
      vService.Free;
    end;
  finally
    vStream.Free;
  end;
end;

class procedure TAnexosController.DownloadAnexo(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vTenantId, vAnexoId: Int64;
  vService: TAnexoService;
  vFileStream: TFileStream;
  vNomeOriginal, vMimeType: string;
begin
  vTenantId := Req.Session<Int64>('tenant_id');
  if vTenantId <= 0 then vTenantId := 1;
  vAnexoId := StrToInt64Def(Req.Params['anexo_id'], 0);

  vService := TAnexoService.Create;
  try
    vFileStream := vService.ObterArquivoParaDownload(vTenantId, 
      vAnexoId, vNomeOriginal, vMimeType);

    Res.RawWebResponse.ContentType := vMimeType;
    Res.RawWebResponse.SetCustomHeader('Content-Disposition', 
      Format('attachment; filename="%s"', [vNomeOriginal]));
    Res.RawWebResponse.ContentLength := vFileStream.Size;

    Res.Send<TStream>(vFileStream);
  finally
    vService.Free;
  end;
end;

end.
