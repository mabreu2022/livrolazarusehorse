unit Middlewares.CorrelationId;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  Horse;

type
  TMiddlewareCorrelationId = class
  private
    class function GerarUUID: string;
  public
    class procedure Middleware(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
  end;

implementation

{ TMiddlewareCorrelationId }

class function TMiddlewareCorrelationId.GerarUUID: string;
var
  vGUID: TGUID;
begin
  CreateGUID(vGUID);
  Result := LowerCase(Copy(GUIDToString(vGUID), 2, 36));
end;

class procedure TMiddlewareCorrelationId.Middleware(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vCorrelationId: string;
begin
  vCorrelationId := Req.Headers.Field('X-Correlation-ID').AsString;

  if Trim(vCorrelationId) = '' then
    vCorrelationId := GerarUUID;

  Res.RawWebResponse.SetCustomHeader('X-Correlation-ID', 
    vCorrelationId);

  Next();
end;

end.
