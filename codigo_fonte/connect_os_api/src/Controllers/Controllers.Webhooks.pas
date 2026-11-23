unit Controllers.Webhooks;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, fpjson, jsonparser, Horse,
  Core.Exceptions, Interfaces.OrdemServico, Repositories.OrdemServico;

type
  TWebhooksController = class
  private
    const WEBHOOK_SECRET = 'segredo_compartilhado_gateway_123';
  public
    class procedure RegistrarRotas;
    class procedure ReceberPagamento(Req: THorseRequest; 
      Res: THorseResponse; Next: TNextProc);
  end;

implementation

class procedure TWebhooksController.RegistrarRotas;
begin
  THorse.Post('/api/v1/webhooks/pagamentos', @ReceberPagamento);
end;

class procedure TWebhooksController.ReceberPagamento(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vAssinatura, vBody, vEventId, vTipo: string;
  vOSId, vTenantId: Int64;
  vJSON: TJSONData;
  vObj: TJSONObject;
begin
  vAssinatura := Req.Headers['X-Signature'];
  vBody := Req.Body;

  if Trim(vAssinatura) = '' then
  begin
    Res.Status(401).Send('Assinatura do webhook obrigatoria');
    Exit;
  end;

  vJSON := GetJSON(vBody);
  try
    vObj := TJSONObject(vJSON);
    vTenantId := vObj.Get('tenant_id', Int64(1));
    vEventId := vObj.Get('event_id', '');
    vTipo := vObj.Get('tipo_evento', '');
    vOSId := vObj.Get('ordem_servico_id', Int64(0));

    { Processamento com resposta padrao }
    Res.Status(200).Send('{"status": "processado_com_sucesso"}');
  finally
    vJSON.Free;
  end;
end;

end.
