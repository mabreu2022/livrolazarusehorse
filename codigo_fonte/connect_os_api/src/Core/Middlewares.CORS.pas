unit Middlewares.CORS;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  Horse;

type
  TMiddlewareCORS = class
  private
    class var FOrigensPermitidas: string;
  public
    class procedure Configurar(const AOrigens: string);
    class procedure Middleware(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
  end;

implementation

{ TMiddlewareCORS }

class procedure TMiddlewareCORS.Configurar(const AOrigens: string);
begin
  FOrigensPermitidas := AOrigens;
end;

class procedure TMiddlewareCORS.Middleware(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vOrigin: string;
begin
  vOrigin := Req.Headers.Field('Origin').AsString;

  if FOrigensPermitidas = '*' then
    Res.RawWebResponse.SetCustomHeader(
      'Access-Control-Allow-Origin', '*')
  else if vOrigin <> '' then
    Res.RawWebResponse.SetCustomHeader('Access-Control-Allow-Origin', 
      vOrigin);

  Res.RawWebResponse.SetCustomHeader('Access-Control-Allow-Methods', 
    'GET, POST, PUT, PATCH, DELETE, OPTIONS');
  Res.RawWebResponse.SetCustomHeader('Access-Control-Allow-Headers', 
    'Content-Type, Authorization, X-Tenant-ID, X-Correlation-ID');
  Res.RawWebResponse.SetCustomHeader(
    'Access-Control-Allow-Credentials', 'true');
  Res.RawWebResponse.SetCustomHeader('Access-Control-Max-Age', '86400');

  if SameText(Req.RawWebRequest.Method, 'OPTIONS') then
  begin
    Res.Status(THTTPStatus.NoContent);
    Exit;
  end;

  Next();
end;

end.
