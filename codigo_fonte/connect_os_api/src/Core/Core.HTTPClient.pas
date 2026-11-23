unit Core.HTTPClient;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, fphttpclient, opensslsockets, Core.Exceptions;

type
  { Contrato para o cliente HTTP desacoplado }
  IHTTPClient = interface
    ['{3D4E5F6A-7B8C-9D0E-1F2A-3B4C5D6E7F80}']
    function Get(const AURL: string; out AStatusCode: Integer): string;
    function Post(const AURL, ABody: string; 
      out AStatusCode: Integer): string;
  end;

  { Implementacao concreta baseada em TFPHTTPClient }
  TFPHTTPClientWrapper = class(TInterfacedObject, IHTTPClient)
  private
    FConnectTimeout: Integer;
    FIOTimeout: Integer;
    function CriarClient: TFPHTTPClient;
  public
    constructor Create(const AConnectTimeout: Integer = 5000; 
      const AIOTimeout: Integer = 10000);
    function Get(const AURL: string; out AStatusCode: Integer): string;
    function Post(const AURL, ABody: string; 
      out AStatusCode: Integer): string;
  end;

implementation

constructor TFPHTTPClientWrapper.Create(const AConnectTimeout: Integer; 
  const AIOTimeout: Integer);
begin
  inherited Create;
  FConnectTimeout := AConnectTimeout;
  FIOTimeout := AIOTimeout;
end;

function TFPHTTPClientWrapper.CriarClient: TFPHTTPClient;
begin
  Result := TFPHTTPClient.Create(nil);
  Result.ConnectTimeout := FConnectTimeout;
  Result.IOTimeout := FIOTimeout;
  Result.AllowRedirect := True;
  Result.AddHeader('User-Agent', 'ConnectOS-API/1.0 (Free Pascal)');
  Result.AddHeader('Accept', 'application/json');
end;

function TFPHTTPClientWrapper.Get(const AURL: string; 
  out AStatusCode: Integer): string;
var
  vClient: TFPHTTPClient;
begin
  vClient := CriarClient;
  try
    try
      Result := vClient.Get(AURL);
      AStatusCode := vClient.ResponseStatusCode;
    except
      on E: Exception do
      begin
        AStatusCode := 503;
        raise EAppException.Create(
          'Falha na comunicacao com servico externo: ' + E.Message);
      end;
    end;
  finally
    vClient.Free;
  end;
end;

function TFPHTTPClientWrapper.Post(const AURL, ABody: string; 
  out AStatusCode: Integer): string;
var
  vClient: TFPHTTPClient;
  vInput, vOutput: TStringStream;
begin
  vClient := CriarClient;
  vInput := TStringStream.Create(ABody);
  vOutput := TStringStream.Create('');
  try
    vClient.AddHeader('Content-Type', 'application/json');
    vClient.RequestBody := vInput;
    try
      vClient.Post(AURL, vOutput);
      AStatusCode := vClient.ResponseStatusCode;
      Result := vOutput.DataString;
    except
      on E: Exception do
      begin
        AStatusCode := 503;
        raise EAppException.Create(
          'Falha no envio de dados para servico externo: ' + E.Message);
      end;
    end;
  finally
    vOutput.Free;
    vInput.Free;
    vClient.Free;
  end;
end;

end.
