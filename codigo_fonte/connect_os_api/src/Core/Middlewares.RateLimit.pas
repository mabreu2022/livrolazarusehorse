unit Middlewares.RateLimit;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  syncobjs,
  Horse,
  Core.ProblemDetails;

type
  TRateLimitEntry = record
    IP: string;
    Contador: Integer;
    JanelaInicio: QWord;
  end;

  TMiddlewareRateLimit = class
  private
    class var FSection: TCriticalSection;
    class var FTabela: array of TRateLimitEntry;
    class var FLimiteRequisicoes: Integer;
    class var FJanelaSegundos: Integer;
    class function VerificarELimitar(const AIP: string): Boolean;
  public
    class procedure Configurar(ALimitePorJanela: Integer; 
      AJanelaSegundos: Integer);
    class procedure Middleware(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
    class procedure Inicializar;
    class procedure Finalizar;
  end;

implementation

{ TMiddlewareRateLimit }

class procedure TMiddlewareRateLimit.Inicializar;
begin
  FSection := TCriticalSection.Create;
  SetLength(FTabela, 0);
  FLimiteRequisicoes := 60;
  FJanelaSegundos := 60;
end;

class procedure TMiddlewareRateLimit.Finalizar;
begin
  FSection.Free;
  SetLength(FTabela, 0);
end;

class procedure TMiddlewareRateLimit.Configurar(
  ALimitePorJanela: Integer; AJanelaSegundos: Integer);
begin
  FLimiteRequisicoes := ALimitePorJanela;
  FJanelaSegundos := AJanelaSegundos;
end;

class function TMiddlewareRateLimit.VerificarELimitar(
  const AIP: string): Boolean;
var
  vAgora: QWord;
  vDeltaSegundos: QWord;
  i: Integer;
  vIndice: Integer;
begin
  Result := True;
  vAgora := GetTickCount64;

  FSection.Enter;
  try
    vIndice := -1;
    for i := 0 to High(FTabela) do
    begin
      if FTabela[i].IP = AIP then
      begin
        vIndice := i;
        Break;
      end;
    end;

    if vIndice = -1 then
    begin
      vIndice := Length(FTabela);
      SetLength(FTabela, vIndice + 1);
      FTabela[vIndice].IP := AIP;
      FTabela[vIndice].Contador := 1;
      FTabela[vIndice].JanelaInicio := vAgora;
      Exit(True);
    end;

    vDeltaSegundos := (vAgora - FTabela[vIndice].JanelaInicio) div 1000;

    if vDeltaSegundos >= QWord(FJanelaSegundos) then
    begin
      FTabela[vIndice].Contador := 1;
      FTabela[vIndice].JanelaInicio := vAgora;
      Exit(True);
    end;

    Inc(FTabela[vIndice].Contador);

    if FTabela[vIndice].Contador > FLimiteRequisicoes then
      Result := False;
  finally
    FSection.Leave;
  end;
end;

class procedure TMiddlewareRateLimit.Middleware(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vIP: string;
begin
  vIP := Req.RawWebRequest.RemoteAddress;
  if Trim(vIP) = '' then
    vIP := '127.0.0.1';

  if not VerificarELimitar(vIP) then
  begin
    Res.RawWebResponse.SetCustomHeader('Retry-After', 
      IntToStr(FJanelaSegundos));

    TProblemDetails.CreateNew
      .SetType('https://api.connectos.com/erros/limite-requisicoes')
      .SetTitle('Muitas Requisicoes')
      .SetStatus(429)
      .SetDetail('Limite de taxa excedido. Aguarde antes de retentar.')
      .SetInstance(Req.RawWebRequest.PathInfo)
      .SendTo(Res);
    Exit;
  end;

  Next();
end;

initialization
  TMiddlewareRateLimit.Inicializar;

finalization
  TMiddlewareRateLimit.Finalizar;

end.
