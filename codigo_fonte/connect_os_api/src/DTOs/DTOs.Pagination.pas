unit DTOs.Pagination;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, fpjson;

type
  { Representa os parametros de paginacao recebidos via Query String }
  TPaginationRequest = class
  private
    FPagina: Integer;
    FLimite: Integer;
    FCampoOrdenacao: string;
    FOrdemDescendente: Boolean;
    function GetOffset: Integer;
  public
    constructor Create;
    procedure DefinirPaginacao(const APagina, ALimite: Integer);
    procedure DefinirOrdenacao(const ACampo, ADirecao: string; 
      const ACamposValidos: array of string);
    property Pagina: Integer read FPagina write FPagina;
    property Limite: Integer read FLimite write FLimite;
    property Offset: Integer read GetOffset;
    property CampoOrdenacao: string read FCampoOrdenacao;
    property OrdemDescendente: Boolean read FOrdemDescendente;
  end;

  { Representa os metadados de navegacao no envelope de resposta }
  TPaginationMetadata = class
  private
    FTotalRegistros: Int64;
    FTotalPaginas: Integer;
    FPaginaAtual: Integer;
    FLimite: Integer;
  public
    constructor Create(const ATotal: Int64; const APagina, 
      ALimite: Integer);
    function ToJSONObject: TJSONObject;
    property TotalRegistros: Int64 read FTotalRegistros;
    property TotalPaginas: Integer read FTotalPaginas;
    property PaginaAtual: Integer read FPaginaAtual;
    property Limite: Integer read FLimite;
  end;

implementation

{ TPaginationRequest }

constructor TPaginationRequest.Create;
begin
  inherited Create;
  FPagina := 1;
  FLimite := 10;
  FCampoOrdenacao := 'id';
  FOrdemDescendente := True;
end;

procedure TPaginationRequest.DefinirPaginacao(const APagina, 
  ALimite: Integer);
begin
  if APagina > 0 then
    FPagina := APagina
  else
    FPagina := 1;

  if (ALimite > 0) and (ALimite <= 100) then
    FLimite := ALimite
  else if ALimite > 100 then
    FLimite := 100
  else
    FLimite := 10;
end;

procedure TPaginationRequest.DefinirOrdenacao(const ACampo, 
  ADirecao: string; const ACamposValidos: array of string);
var
  i: Integer;
  vCampoLimpo: string;
  vValido: Boolean;
begin
  vCampoLimpo := LowerCase(Trim(ACampo));
  vValido := False;

  for i := Low(ACamposValidos) to High(ACamposValidos) do
  begin
    if LowerCase(ACamposValidos[i]) = vCampoLimpo then
    begin
      vValido := True;
      FCampoOrdenacao := vCampoLimpo;
      Break;
    end;
  end;

  if not vValido then
    FCampoOrdenacao := 'id';

  FOrdemDescendente := (LowerCase(Trim(ADirecao)) = 'desc');
end;

function TPaginationRequest.GetOffset: Integer;
begin
  Result := (FPagina - 1) * FLimite;
end;

{ TPaginationMetadata }

constructor TPaginationMetadata.Create(const ATotal: Int64; 
  const APagina, ALimite: Integer);
begin
  inherited Create;
  FTotalRegistros := ATotal;
  FPaginaAtual := APagina;
  FLimite := ALimite;

  if (FLimite > 0) and (FTotalRegistros > 0) then
    FTotalPaginas := ((FTotalRegistros + FLimite - 1) div FLimite)
  else
    FTotalPaginas := 0;
end;

function TPaginationMetadata.ToJSONObject: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('total_registros', FTotalRegistros);
  Result.Add('total_paginas', FTotalPaginas);
  Result.Add('pagina_atual', FPaginaAtual);
  Result.Add('limite_por_pagina', FLimite);
  Result.Add('tem_proxima_pagina', (FPaginaAtual < FTotalPaginas));
  Result.Add('tem_pagina_anterior', (FPaginaAtual > 1));
end;

end.
