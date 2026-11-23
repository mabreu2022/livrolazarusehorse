unit Core.SQLBuilder;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, sqldb;

type
  { Representa um parametro tipado a ser injetado na query }
  TParamType = (ptString, ptInt64, ptFloat, ptDateTime);

  TFilterParam = record
    Nome: string;
    Tipo: TParamType;
    ValorString: string;
    ValorInt64: Int64;
    ValorFloat: Double;
    ValorDateTime: TDateTime;
  end;

  { Construtor dinâmico de clausulas WHERE e ORDER BY seguras }
  TSQLFilterBuilder = class
  private
    FClausulas: TStringList;
    FParams: array of TFilterParam;
    procedure AdicionarParametro(const ANome: string; 
      ATipo: TParamType; const AValStr: string; AValInt: Int64; 
      AValFloat: Double; AValDate: TDateTime);
  public
    constructor Create;
    destructor Destroy; override;
    procedure AdicionarCondicao(const ACondicao: string);
    procedure AdicionarFiltroTexto(const ACampo, ANomeParam, 
      AValor: string);
    procedure AdicionarFiltroInt64(const ACampo, ANomeParam: string; 
      const AValor: Int64);
    procedure AdicionarFiltroFloat(const ACampo, ANomeParam: string; 
      const AValor: Double);
    function MontarClausulaWhere: string;
    procedure AplicarParametros(AQry: TSQLQuery);
  end;

implementation

constructor TSQLFilterBuilder.Create;
begin
  inherited Create;
  FClausulas := TStringList.Create;
end;

destructor TSQLFilterBuilder.Destroy;
begin
  FClausulas.Free;
  inherited Destroy;
end;

procedure TSQLFilterBuilder.AdicionarParametro(const ANome: string; 
  ATipo: TParamType; const AValStr: string; AValInt: Int64; 
  AValFloat: Double; AValDate: TDateTime);
var
  vIdx: Integer;
begin
  vIdx := Length(FParams);
  SetLength(FParams, vIdx + 1);
  FParams[vIdx].Nome := ANome;
  FParams[vIdx].Tipo := ATipo;
  FParams[vIdx].ValorString := AValStr;
  FParams[vIdx].ValorInt64 := AValInt;
  FParams[vIdx].ValorFloat := AValFloat;
  FParams[vIdx].ValorDateTime := AValDate;
end;

procedure TSQLFilterBuilder.AdicionarCondicao(const ACondicao: string);
begin
  FClausulas.Add(ACondicao);
end;

procedure TSQLFilterBuilder.AdicionarFiltroTexto(const ACampo, 
  ANomeParam, AValor: string);
begin
  if Trim(AValor) <> '' then
  begin
    FClausulas.Add(Format('%s = :%s', [ACampo, ANomeParam]));
    AdicionarParametro(ANomeParam, ptString, Trim(AValor), 0, 0.0, 0);
  end;
end;

procedure TSQLFilterBuilder.AdicionarFiltroInt64(const ACampo, 
  ANomeParam: string; const AValor: Int64);
begin
  if AValor > 0 then
  begin
    FClausulas.Add(Format('%s = :%s', [ACampo, ANomeParam]));
    AdicionarParametro(ANomeParam, ptInt64, '', AValor, 0.0, 0);
  end;
end;

procedure TSQLFilterBuilder.AdicionarFiltroFloat(const ACampo, 
  ANomeParam: string; const AValor: Double);
begin
  if AValor > 0 then
  begin
    FClausulas.Add(Format('%s = :%s', [ACampo, ANomeParam]));
    AdicionarParametro(ANomeParam, ptFloat, '', 0, AValor, 0);
  end;
end;

function TSQLFilterBuilder.MontarClausulaWhere: string;
var
  i: Integer;
begin
  if FClausulas.Count = 0 then
    Exit('');

  Result := ' WHERE ' + FClausulas[0];
  for i := 1 to FClausulas.Count - 1 do
    Result := Result + ' AND ' + FClausulas[i];
end;

procedure TSQLFilterBuilder.AplicarParametros(AQry: TSQLQuery);
var
  i: Integer;
begin
  for i := 0 to High(FParams) do
  begin
    case FParams[i].Tipo of
      ptString:
        AQry.ParamByName(FParams[i].Nome).AsString := 
          FParams[i].ValorString;
      ptInt64:
        AQry.ParamByName(FParams[i].Nome).AsLargeInt := 
          FParams[i].ValorInt64;
      ptFloat:
        AQry.ParamByName(FParams[i].Nome).AsFloat := 
          FParams[i].ValorFloat;
      ptDateTime:
        AQry.ParamByName(FParams[i].Nome).AsDateTime := 
          FParams[i].ValorDateTime;
    end;
  end;
end;

end.
