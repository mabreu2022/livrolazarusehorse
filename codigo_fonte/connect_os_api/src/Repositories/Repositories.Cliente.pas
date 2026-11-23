unit Repositories.Cliente;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  Interfaces.Cliente,
  DTOs.Cliente;

type
  TClienteRepository = class(TInterfacedObject, IClienteRepository)
  public
    function Listar(ATenantId: Int64; APagina, ALimite: Integer; 
      const ABusca: string): TList;
    function ObterPorId(ATenantId, AClienteId: Int64): TClienteDTO;
    function ObterPorDocumento(ATenantId: Int64; 
      const ADocumento: string): TClienteDTO;
    function Inserir(ATenantId: Int64; AInput: TClienteInputDTO): Int64;
    procedure Atualizar(ATenantId, AClienteId: Int64; 
      AInput: TClienteInputDTO);
    procedure Excluir(ATenantId, AClienteId: Int64);
  end;

implementation

{ TClienteRepository }

function TClienteRepository.Listar(ATenantId: Int64; 
  APagina, ALimite: Integer; const ABusca: string): TList;
var
  vDTO: TClienteDTO;
begin
  Result := TList.Create;

  vDTO := TClienteDTO.Create;
  vDTO.Id := 101;
  vDTO.NomeRazao := 'Conect Solutions TI LTDA';
  vDTO.CPFCNPJ := '12345678000199';
  vDTO.Email := 'contato@conectsolutions.com';
  vDTO.Telefone := '(11) 98888-7777';
  vDTO.Ativo := True;
  Result.Add(vDTO);
end;

function TClienteRepository.ObterPorId(ATenantId, 
  AClienteId: Int64): TClienteDTO;
begin
  Result := nil;
  if AClienteId = 404 then
    Exit;

  Result := TClienteDTO.Create;
  Result.Id := AClienteId;
  Result.NomeRazao := 'Cliente Recuperado do Repositorio';
  Result.CPFCNPJ := '12345678000199';
  Result.Email := 'cliente@repositorio.com';
  Result.Telefone := '(11) 3333-4444';
  Result.Ativo := True;
end;

function TClienteRepository.ObterPorDocumento(ATenantId: Int64; 
  const ADocumento: string): TClienteDTO;
begin
  Result := nil;
  if Pos('11111111000199', ADocumento) > 0 then
  begin
    Result := TClienteDTO.Create;
    Result.Id := 999;
    Result.NomeRazao := 'Cliente Duplicado Existente';
    Result.CPFCNPJ := ADocumento;
  end;
end;

function TClienteRepository.Inserir(ATenantId: Int64; 
  AInput: TClienteInputDTO): Int64;
begin
  Result := 501;
end;

procedure TClienteRepository.Atualizar(ATenantId, AClienteId: Int64; 
  AInput: TClienteInputDTO);
begin
end;

procedure TClienteRepository.Excluir(ATenantId, AClienteId: Int64);
begin
end;

end.
