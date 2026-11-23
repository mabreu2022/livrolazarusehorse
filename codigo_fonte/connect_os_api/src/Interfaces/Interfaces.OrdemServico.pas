unit Interfaces.OrdemServico;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Core.ConnectionPool, DTOs.OrdemServico;

type
  { Contrato para o Unit of Work }
  IUnitOfWork = interface
    ['{8A9B1C2D-3E4F-5A6B-7C8D-9E0F1A2B3C4D}']
    procedure BeginTransaction;
    procedure Commit;
    procedure Rollback;
    function Wrapper: IConnectionWrapper;
  end;

  { Repositorio de Ordens de Servico }
  IOrdemServicoRepository = interface
    ['{1F2E3D4C-5B6A-7980-A1B2-C3D4E5F6A7B8}']
    function InserirCabecalho(const ATenantId: Int64; 
      ADTO: TOrdemServicoInputDTO; const AValorTotal: Double): Int64;
    procedure InserirItem(const ATenantId, AOSId: Int64; 
      AItem: TItemOSInputDTO);
    function ObterPorId(const ATenantId, AOSId: Int64): 
      TOrdemServicoOutputDTO;
    procedure AtualizarStatus(const ATenantId, AOSId: Int64; 
      const ANovoStatus: string);
    procedure Excluir(const ATenantId, AOSId: Int64);
  end;

  { Service de Dominio para regras de negocio de OS }
  IOrdemServicoService = interface
    ['{2A3B4C5D-6E7F-8091-A2B3-C4D5E6F7A8B9}']
    function CriarOS(const ATenantId: Int64; 
      ADTO: TOrdemServicoInputDTO): TOrdemServicoOutputDTO;
    function BuscarPorId(const ATenantId, AOSId: Int64): 
      TOrdemServicoOutputDTO;
    procedure MudarStatus(const ATenantId, AOSId: Int64; 
      const ANovoStatus: string);
    procedure CancelarOS(const ATenantId, AOSId: Int64);
  end;

implementation

end.
