unit Middlewares.AuthJWT;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  Horse,
  Core.Security,
  Core.Exceptions;

type
  TMiddlewareAuthJWT = class
  private
    class var FSecretKey: string;
  public
    class procedure Configurar(const ASecretKey: string);
    class procedure Middleware(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
  end;

implementation

{ TMiddlewareAuthJWT }

class procedure TMiddlewareAuthJWT.Configurar(const ASecretKey: string);
begin
  FSecretKey := ASecretKey;
end;

class procedure TMiddlewareAuthJWT.Middleware(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vAuthHeader: string;
  vToken: string;
  vSession: TUserSession;
begin
  if SameText(Req.RawWebRequest.PathInfo, '/ping') or
     SameText(Req.RawWebRequest.PathInfo, '/api/v1/auth/login') or
     SameText(Req.RawWebRequest.PathInfo, '/api/v1/auth/refresh') or
     SameText(Req.RawWebRequest.Method, 'OPTIONS') then
  begin
    Next();
    Exit;
  end;

  vAuthHeader := Req.Headers.Field('Authorization').AsString;
  if Trim(vAuthHeader) = '' then
    raise EUnauthorizedException.Create(
      'Cabecalho de autorizacao ausente');

  if not vAuthHeader.StartsWith('Bearer ', True) then
    raise EUnauthorizedException.Create(
      'Formato de autenticacao invalido. Esperado Bearer <token>');

  vToken := Copy(vAuthHeader, 8, Length(vAuthHeader));

  vSession := TSecurityService.ValidarTokenJWT(vToken, FSecretKey);
  try
    Req.RawWebRequest.SetCustomHeader('X-Authenticated-Tenant', 
      IntToStr(vSession.TenantId));
    Req.RawWebRequest.SetCustomHeader('X-Authenticated-User', 
      IntToStr(vSession.UserId));
    Req.RawWebRequest.SetCustomHeader('X-Authenticated-Role', 
      vSession.Perfil);

    Next();
  finally
    vSession.Free;
  end;
end;

end.
