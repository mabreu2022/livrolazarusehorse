unit Core.ProblemDetails;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  Horse;

type
  TInvalidParam = record
    Campo: string;
    Motivo: string;
  end;

  TProblemDetails = record
  private
    FType: string;
    FTitle: string;
    FStatus: Integer;
    FDetail: string;
    FInstance: string;
    FInvalidParams: array of TInvalidParam;
  public
    class function CreateNew: TProblemDetails; static;
    function SetType(const AType: string): TProblemDetails;
    function SetTitle(const ATitle: string): TProblemDetails;
    function SetStatus(const AStatus: Integer): TProblemDetails;
    function SetDetail(const ADetail: string): TProblemDetails;
    function SetInstance(const AInstance: string): TProblemDetails;
    function AddInvalidParam(const ACampo, AMotivo: string): 
      TProblemDetails;
    function ToJSON: string;
    procedure SendTo(Res: THorseResponse);
  end;

implementation

{ TProblemDetails }

class function TProblemDetails.CreateNew: TProblemDetails;
begin
  Result.FType := 'about:blank';
  Result.FTitle := 'Erro Inesperado';
  Result.FStatus := 500;
  Result.FDetail := '';
  Result.FInstance := '';
  SetLength(Result.FInvalidParams, 0);
end;

function TProblemDetails.SetType(const AType: string): TProblemDetails;
begin
  FType := AType;
  Result := Self;
end;

function TProblemDetails.SetTitle(const ATitle: string): 
  TProblemDetails;
begin
  FTitle := ATitle;
  Result := Self;
end;

function TProblemDetails.SetStatus(const AStatus: Integer): 
  TProblemDetails;
begin
  FStatus := AStatus;
  Result := Self;
end;

function TProblemDetails.SetDetail(const ADetail: string): 
  TProblemDetails;
begin
  FDetail := ADetail;
  Result := Self;
end;

function TProblemDetails.SetInstance(const AInstance: string): 
  TProblemDetails;
begin
  FInstance := AInstance;
  Result := Self;
end;

function TProblemDetails.AddInvalidParam(const ACampo, AMotivo: string): 
  TProblemDetails;
var
  vLen: Integer;
begin
  vLen := Length(FInvalidParams);
  SetLength(FInvalidParams, vLen + 1);
  FInvalidParams[vLen].Campo := ACampo;
  FInvalidParams[vLen].Motivo := AMotivo;
  Result := Self;
end;

function TProblemDetails.ToJSON: string;
var
  vJSON: string;
  i: Integer;
begin
  vJSON := '{' +
           '"type":"' + FType + '",' +
           '"title":"' + FTitle + '",' +
           '"status":' + IntToStr(FStatus) + ',' +
           '"detail":"' + FDetail + '"';

  if FInstance <> '' then
    vJSON := vJSON + ',"instance":"' + FInstance + '"';

  if Length(FInvalidParams) > 0 then
  begin
    vJSON := vJSON + ',"invalidParams":[';
    for i := 0 to High(FInvalidParams) do
    begin
      if i > 0 then
        vJSON := vJSON + ',';
      vJSON := vJSON + '{"campo":"' + FInvalidParams[i].Campo + '",' +
                       '"motivo":"' + FInvalidParams[i].Motivo + '"}';
    end;
    vJSON := vJSON + ']';
  end;

  vJSON := vJSON + '}';
  Result := vJSON;
end;

procedure TProblemDetails.SendTo(Res: THorseResponse);
begin
  Res.RawWebResponse.ContentType := 
    'application/problem+json; charset=utf-8';
  Res.Send(ToJSON)
     .Status(THTTPStatus(FStatus));
end;

end.
