unit Controllers.Auth;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  fpjson,
  Horse,
  Core.Security,
  Core.Exceptions;

type
  TControllersAuth = class
  private
    class var FSecretKey: string;
    class procedure Login(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
    class procedure Refresh(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
    class procedure Logout(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
  public
    class procedure Configurar(const ASecretKey: string);
    class procedure Registry;
  end;

implementation

{ TControllersAuth }

class procedure TControllersAuth.Configurar(const ASecretKey: string);
begin
  FSecretKey := ASecretKey;
end;

class procedure TControllersAuth.Login(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vBody: TJSONObject;
  vEmail, vSenha: string;
  vSession: TUserSession;
  vAccessToken, vRefreshToken: string;
  vResposta: TJSONObject;
begin
  vBody := Req.Body<TJSONObject>();
  if not Assigned(vBody) then
    raise EAppException.Create('Payload de login ausente', 400);

  vEmail := Trim(vBody.Get('email', ''));
  vSenha := Trim(vBody.Get('senha', ''));

  if (vEmail <> 'admin@conectsolutions.com') or 
     (vSenha <> 'Admin123@Segura') then
    raise EUnauthorizedException.Create('Email ou senha incorretos');

  vSession := TUserSession.Create;
  try
    vSession.TenantId := 1;
    vSession.UserId := 1;
    vSession.Nome := 'Administrador do Sistema';
    vSession.Email := vEmail;
    vSession.Perfil := 'ADMIN';

    vAccessToken := TSecurityService.GerarTokenJWT(
      vSession, FSecretKey, 15);

    vRefreshToken := 
      LowerCase(Copy(GUIDToString(TGUID.NewGuid), 2, 36));

    vResposta := TJSONObject.Create;
    vResposta.Add('access_token', vAccessToken);
    vResposta.Add('token_type', 'Bearer');
    vResposta.Add('expires_in', 900);
    vResposta.Add('refresh_token', vRefreshToken);

    Res.Send(vResposta)
       .Status(THTTPStatus.OK);
  finally
    vSession.Free;
  end;
end;

class procedure TControllersAuth.Refresh(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vBody: TJSONObject;
  vRefreshToken: string;
  vSession: TUserSession;
  vNovoAccessToken: string;
  vResposta: TJSONObject;
begin
  vBody := Req.Body<TJSONObject>();
  if not Assigned(vBody) then
    raise EAppException.Create('Corpo com refresh_token ausente', 400);

  vRefreshToken := Trim(vBody.Get('refresh_token', ''));
  if Length(vRefreshToken) < 10 then
    raise EUnauthorizedException.Create('Refresh token invalido');

  vSession := TUserSession.Create;
  try
    vSession.TenantId := 1;
    vSession.UserId := 1;
    vSession.Nome := 'Administrador do Sistema';
    vSession.Email := 'admin@conectsolutions.com';
    vSession.Perfil := 'ADMIN';

    vNovoAccessToken := TSecurityService.GerarTokenJWT(
      vSession, FSecretKey, 15);

    vResposta := TJSONObject.Create;
    vResposta.Add('access_token', vNovoAccessToken);
    vResposta.Add('token_type', 'Bearer');
    vResposta.Add('expires_in', 900);

    Res.Send(vResposta)
       .Status(THTTPStatus.OK);
  finally
    vSession.Free;
  end;
end;

class procedure TControllersAuth.Logout(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
begin
  Res.Status(THTTPStatus.NoContent);
end;

class procedure TControllersAuth.Registry;
begin
  THorse.Post('/api/v1/auth/login', @Login);
  THorse.Post('/api/v1/auth/refresh', @Refresh);
  THorse.Post('/api/v1/auth/logout', @Logout);
end;

end.
