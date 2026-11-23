unit Services.OrdemServico;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Core.Exceptions, DTOs.OrdemServico,
  Interfaces.OrdemServico, Repositories.OrdemServico;

type
  { Implementacao de regras de negocio da OS }
  TOrdemServicoService = class(TInterfacedObject, IOrdemServicoService)
  private
    function CalcularTotal(ADTO: TOrdemServicoInputDTO): Double;
    procedure ValidarTransicaoStatus(const AStatusAtual, 
      ANovoStatus: string);
  public
    function CriarOS(const ATenantId: Int64; 
      ADTO: TOrdemServicoInputDTO): TOrdemServicoOutputDTO;
    function BuscarPorId(const ATenantId, AOSId: Int64): 
      TOrdemServicoOutputDTO;
    procedure MudarStatus(const ATenantId, AOSId: Int64; 
      const ANovoStatus: string);
    procedure CancelarOS(const ATenantId, AOSId: Int64);
  end;

implementation

function TOrdemServicoService.CalcularTotal(
  ADTO: TOrdemServicoInputDTO): Double;
var
  i: Integer;
begin
  Result := 0.0;
  for i := 0 to ADTO.TotalItens - 1 do
    Result := Result + (ADTO.Itens[i].Quantidade * 
      ADTO.Itens[i].ValorUnitario);
end;

procedure TOrdemServicoService.ValidarTransicaoStatus(
  const AStatusAtual, ANovoStatus: string);
begin
  if AStatusAtual = ANovoStatus then Exit;

  if (AStatusAtual = 'CONCLUIDA') or (AStatusAtual = 'CANCELADA') then
    raise EBusinessException.Create(
      'Ordem de Servico finalizada nao permite alteracao de status');

  if (AStatusAtual = 'ABERTA') and (ANovoStatus <> 'EM_EXECUCAO') and 
     (ANovoStatus <> 'CANCELADA') then
    raise EBusinessException.Create(
      'OS Aberta so transiciona para EM_EXECUCAO ou CANCELADA');

  if (AStatusAtual = 'EM_EXECUCAO') and 
     (ANovoStatus <> 'CONCLUIDA') and (ANovoStatus <> 'CANCELADA') then
    raise EBusinessException.Create(
      'OS Em Execucao so transiciona para CONCLUIDA ou CANCELADA');
end;

function TOrdemServicoService.CriarOS(const ATenantId: Int64; 
  ADTO: TOrdemServicoInputDTO): TOrdemServicoOutputDTO;
var
  vUoW: IUnitOfWork;
  vRepo: IOrdemServicoRepository;
  vTotal: Double;
  vNovoId: Int64;
  i: Integer;
begin
  ADTO.Validar;
  vTotal := CalcularTotal(ADTO);

  vUoW := TUnitOfWork.Create;
  vRepo := TOrdemServicoRepository.Create(vUoW);

  vUoW.BeginTransaction;
  try
    vNovoId := vRepo.InserirCabecalho(ATenantId, ADTO, vTotal);
    for i := 0 to ADTO.TotalItens - 1 do
      vRepo.InserirItem(ATenantId, vNovoId, ADTO.Itens[i]);

    vUoW.Commit;
  except
    vUoW.Rollback;
    raise;
  end;

  Result := vRepo.ObterPorId(ATenantId, vNovoId);
end;

function TOrdemServicoService.BuscarPorId(const ATenantId, 
  AOSId: Int64): TOrdemServicoOutputDTO;
var
  vUoW: IUnitOfWork;
  vRepo: IOrdemServicoRepository;
begin
  vUoW := TUnitOfWork.Create;
  vRepo := TOrdemServicoRepository.Create(vUoW);
  Result := vRepo.ObterPorId(ATenantId, AOSId);
  if not Assigned(Result) then
    raise ENotFoundException.Create(
      Format('Ordem de Servico %d nao encontrada', [AOSId]));
end;

procedure TOrdemServicoService.MudarStatus(const ATenantId, 
  AOSId: Int64; const ANovoStatus: string);
var
  vUoW: IUnitOfWork;
  vRepo: IOrdemServicoRepository;
  vOS: TOrdemServicoOutputDTO;
  vStatusUpper: string;
begin
  vStatusUpper := UpperCase(Trim(ANovoStatus));
  vUoW := TUnitOfWork.Create;
  vRepo := TOrdemServicoRepository.Create(vUoW);

  vOS := vRepo.ObterPorId(ATenantId, AOSId);
  if not Assigned(vOS) then
    raise ENotFoundException.Create(
      Format('Ordem de Servico %d nao encontrada', [AOSId]));
  try
    ValidarTransicaoStatus(vOS.Status, vStatusUpper);
    vUoW.BeginTransaction;
    try
      vRepo.AtualizarStatus(ATenantId, AOSId, vStatusUpper);
      vUoW.Commit;
    except
      vUoW.Rollback;
      raise;
    end;
  finally
    vOS.Free;
  end;
end;

procedure TOrdemServicoService.CancelarOS(const ATenantId, 
  AOSId: Int64);
begin
  MudarStatus(ATenantId, AOSId, 'CANCELADA');
end;

end.
