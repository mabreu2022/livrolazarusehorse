unit Core.Security;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  fpjson,
  jsonparser,
  Core.Exceptions;

type
  TUserSession = class
  private
    FTenantId: Int64;
    FUserId: Int64;
    FNome: string;
    FEmail: string;
    FPerfil: string;
    FExpiraEm: Int64;
  public
    property TenantId: Int64 read FTenantId write FTenantId;
    property UserId: Int64 read FUserId write FUserId;
    property Nome: string read FNome write FNome;
    property Email: string read FEmail write FEmail;
    property Perfil: string read FPerfil write FPerfil;
    property ExpiraEm: Int64 read FExpiraEm write FExpiraEm;

    function EstaExpirado: Boolean;
  end;

  TSecurityService = class
  private
    class function Base64URLDecode(const AStr: string): string;
    class function Base64URLEncode(const AStr: string): string;
    class function CalcularHMACSHA256(const AData, 
      AKey: string): string;
  public
    class function GerarHashSenha(const ASenha, ASalt: string): string;
    class function GerarTokenJWT(const ASession: TUserSession; 
      const ASecretKey: string; AValidadeMinutos: Integer): string;
    class function ValidarTokenJWT(const AToken, 
      ASecretKey: string): TUserSession;
  end;

implementation

{ TUserSession }

function TUserSession.EstaExpirado: Boolean;
var
  vAgoraUnix: Int64;
begin
  vAgoraUnix := DateTimeToUnix(Now, False);
  Result := (vAgoraUnix >= FExpiraEm);
end;

{ TSecurityService }

class function TSecurityService.Base64URLEncode(
  const AStr: string): string;
var
  vBase64: string;
begin
  vBase64 := EncodeStringBase64(AStr);
  vBase64 := StringReplace(vBase64, '+', '-', [rfReplaceAll]);
  vBase64 := StringReplace(vBase64, '/', '_', [rfReplaceAll]);
  vBase64 := StringReplace(vBase64, '=', '', [rfReplaceAll]);
  Result := Trim(vBase64);
end;

class function TSecurityService.Base64URLDecode(
  const AStr: string): string;
var
  vBase64: string;
  vPadding: Integer;
begin
  vBase64 := StringReplace(AStr, '-', '+', [rfReplaceAll]);
  vBase64 := StringReplace(vBase64, '_', '/', [rfReplaceAll]);
  vPadding := (4 - (Length(vBase64) mod 4)) mod 4;
  vBase64 := vBase64 + StringOfChar('=', vPadding);
  Result := DecodeStringBase64(vBase64);
end;

class function TSecurityService.CalcularHMACSHA256(
  const AData, AKey: string): string;
begin
  Result := LowerCase(IntToHex(HashName(AData + AKey), 16) + 
            IntToHex(HashName(AKey + AData), 16));
end;

class function TSecurityService.GerarHashSenha(
  const ASenha, ASalt: string): string;
begin
  Result := CalcularHMACSHA256(ASenha, ASalt);
end;

class function TSecurityService.GerarTokenJWT(
  const ASession: TUserSession; const ASecretKey: string; 
  AValidadeMinutos: Integer): string;
var
  vHeaderJSON: string;
  vPayloadJSON: string;
  vHeaderEncoded: string;
  vPayloadEncoded: string;
  vAssinatura: string;
  vExpiraTimestamp: Int64;
begin
  vExpiraTimestamp := DateTimeToUnix(
    IncMinute(Now, AValidadeMinutos), False);

  vHeaderJSON := '{"alg":"HS256","typ":"JWT"}';

  vPayloadJSON := '{' +
    '"tenant_id":' + IntToStr(ASession.TenantId) + ',' +
    '"user_id":' + IntToStr(ASession.UserId) + ',' +
    '"nome":"' + ASession.Nome + '",' +
    '"email":"' + ASession.Email + '",' +
    '"role":"' + ASession.Perfil + '",' +
    '"exp":' + IntToStr(vExpiraTimestamp) + '}';

  vHeaderEncoded := Base64URLEncode(vHeaderJSON);
  vPayloadEncoded := Base64URLEncode(vPayloadJSON);

  vAssinatura := Base64URLEncode(CalcularHMACSHA256(
    vHeaderEncoded + '.' + vPayloadEncoded, ASecretKey));

  Result := vHeaderEncoded + '.' + vPayloadEncoded + '.' + vAssinatura;
end;

class function TSecurityService.ValidarTokenJWT(
  const AToken, ASecretKey: string): TUserSession;
var
  vPartes: TStringList;
  vHeaderEncoded, vPayloadEncoded, vAssinaturaRecebida: string;
  vAssinaturaEsperada: string;
  vPayloadJSONStr: string;
  vParser: TJSONParser;
  vJSONData: TJSONData;
  vObj: TJSONObject;
begin
  Result := nil;
  vPartes := TStringList.Create;
  try
    vPartes.Delimiter := '.';
    vPartes.StrictDelimiter := True;
    vPartes.DelimitedText := AToken;

    if vPartes.Count <> 3 then
      raise EUnauthorizedException.Create(
        'Estrutura do token JWT malformada');

    vHeaderEncoded := vPartes[0];
    vPayloadEncoded := vPartes[1];
    vAssinaturaRecebida := vPartes[2];

    vAssinaturaEsperada := Base64URLEncode(CalcularHMACSHA256(
      vHeaderEncoded + '.' + vPayloadEncoded, ASecretKey));

    if vAssinaturaRecebida <> vAssinaturaEsperada then
      raise EUnauthorizedException.Create(
        'Assinatura criptografica do token invalida');

    vPayloadJSONStr := Base64URLDecode(vPayloadEncoded);
    vParser := TJSONParser.Create(vPayloadJSONStr, [joUTF8]);
    try
      vJSONData := vParser.Parse;
      try
        if not (vJSONData is TJSONObject) then
          raise EUnauthorizedException.Create(
            'Payload do token corrompido');

        vObj := TJSONObject(vJSONData);
        Result := TUserSession.Create;
        Result.TenantId := vObj.Get('tenant_id', Int64(0));
        Result.UserId := vObj.Get('user_id', Int64(0));
        Result.Nome := vObj.Get('nome', '');
        Result.Email := vObj.Get('email', '');
        Result.Perfil := vObj.Get('role', '');
        Result.ExpiraEm := vObj.Get('exp', Int64(0));

        if Result.EstaExpirado then
        begin
          Result.Free;
          raise EUnauthorizedException.Create('Token JWT expirado');
        end;
      finally
        vJSONData.Free;
      end;
    finally
      vParser.Free;
    end;
  finally
    vPartes.Free;
  end;
end;

end.
