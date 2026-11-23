unit Interfaces.Cliente;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  DTOs.Cliente;

type
  IClienteRepository = interface
    ['{8A5D6E7F-1B2C-3D4E-5F6A-7B8C9D0E1F2A}']
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

  IClienteService = interface
    ['{9B6E7F8A-2C3D-4E5F-6A7B-8C9D0E1F2A3B}']
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

end.
