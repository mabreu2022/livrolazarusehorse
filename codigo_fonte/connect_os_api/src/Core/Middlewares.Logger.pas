unit Middlewares.Logger;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  Horse;

type
  TMiddlewareLogger = class
  public
    class procedure Middleware(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
  end;

implementation

{ TMiddlewareLogger }

class procedure TMiddlewareLogger.Middleware(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vInicioMS: QWord;
  vDuracaoMS: QWord;
  vMetodo: string;
  vCaminho: string;
  vIPOrigem: string;
  vCorrelationId: string;
  vStatusHTTP: Integer;
begin
  vInicioMS := GetTickCount64;
  vMetodo := Req.RawWebRequest.Method;
  vCaminho := Req.RawWebRequest.PathInfo;
  vIPOrigem := Req.RawWebRequest.RemoteAddress;

  try
    Next();
  finally
    vDuracaoMS := GetTickCount64 - vInicioMS;
    vStatusHTTP := Res.RawWebResponse.Code;
    vCorrelationId := 
      Res.RawWebResponse.GetCustomHeader('X-Correlation-ID');

    WriteLn(Format(
      '[HTTP] %s | %-6s | %-20s | Status: %d | %d ms | CorrID: %s',
      [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now),
       vMetodo,
       vCaminho,
       vStatusHTTP,
       vDuracaoMS,
       vCorrelationId]));
  end;
end;

end.
