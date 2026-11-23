unit Services.Cliente;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  Interfaces.Cliente,
  DTOs.Cliente,
  Core.Exceptions;

type
  TClienteService = class(TInterfacedObject, IClienteService)
  private
    FRepository: IClienteRepository;
  public
    constructor Create(ARepository: IClienteRepository);
    function ListarClientes(ATenantId: Int64; 
      APagina, ALimite: Integer; const ABusca: string): TList;
    function ObterCliente(ATenantId, AClienteId: Int64): TClienteDTO;
    function CadastrarCliente(ATenantId: Int64; 
      AInput: TClienteInputDTO): Int64;
    procedure AtualizarCliente(ATenantId, AClienteId: Int64; 
      AInput: TClienteInputDTO);
    procedure RemoverCliente(ATenantId, AClienteId: Int64);
  end;

implementation

{ TClienteService }

constructor TClienteService.Create(ARepository: IClienteRepository);
begin
  inherited Create;
  FRepository := ARepository;
end;

function TClienteService.ListarClientes(ATenantId: Int64; 
  APagina, ALimite: Integer; const ABusca: string): TList;
begin
  if ATenantId <= 0 then
    raise EBusinessException.Create('Tenant invalido para listagem');

  if ALimite > 100 then
    ALimite := 100;

  Result := FRepository.Listar(ATenantId, APagina, ALimite, ABusca);
end;

function TClienteService.ObterCliente(ATenantId, 
  AClienteId: Int64): TClienteDTO;
begin
  if AClienteId <= 0 then
    raise EBusinessException.Create(
      'Identificador de cliente invalido');

  Result := FRepository.ObterPorId(ATenantId, AClienteId);
  if not Assigned(Result) then
    raise ENotFoundException.Create('Cliente nao localizado na base');
end;

function TClienteService.CadastrarCliente(ATenantId: Int64; 
  AInput: TClienteInputDTO): Int64;
var
  vExistente: TClienteDTO;
begin
  if not Assigned(AInput) then
    raise EBusinessException.Create('Dados do cliente ausentes');

  if Trim(AInput.NomeRazao) = '' then
    raise EBusinessException.Create('Razao Social e campo obrigatorio');

  if Length(Trim(AInput.CPFCNPJ)) < 11 then
    raise EBusinessException.Create('Documento CPF/CNPJ invalido');

  vExistente := FRepository.ObterPorDocumento(
    ATenantId, AInput.CPFCNPJ);
  if Assigned(vExistente) then
  begin
    vExistente.Free;
    raise EConflictException.Create(
      'Ja existe um cliente cadastrado com este CPF/CNPJ');
  end;

  Result := FRepository.Inserir(ATenantId, AInput);
end;

procedure TClienteService.AtualizarCliente(ATenantId, AClienteId: Int64; 
  AInput: TClienteInputDTO);
var
  vAtual: TClienteDTO;
begin
  vAtual := ObterCliente(ATenantId, AClienteId);
  vAtual.Free;

  FRepository.Atualizar(ATenantId, AClienteId, AInput);
end;

procedure TClienteService.RemoverCliente(ATenantId, AClienteId: Int64);
var
  vAtual: TClienteDTO;
begin
  vAtual := ObterCliente(ATenantId, AClienteId);
  vAtual.Free;

  FRepository.Excluir(ATenantId, AClienteId);
end;

end.
