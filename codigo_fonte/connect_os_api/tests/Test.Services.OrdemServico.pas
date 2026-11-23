unit Test.Services.OrdemServico;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, fpcunit, testregistry, Core.Exceptions,
  DTOs.OrdemServico, Interfaces.OrdemServico, Services.OrdemServico;

type
  TTestOrdemServicoService = class(TTestCase)
  private
    FService: TOrdemServicoService;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TesteCalculoTotalItensCorreto;
    procedure TesteRejeitarOSSemItens;
  end;

implementation

procedure TTestOrdemServicoService.SetUp;
begin
  inherited SetUp;
  FService := TOrdemServicoService.Create;
end;

procedure TTestOrdemServicoService.TearDown;
begin
  FService.Free;
  inherited TearDown;
end;

procedure TTestOrdemServicoService.TesteCalculoTotalItensCorreto;
var
  vDTO: TOrdemServicoInputDTO;
  vItem1, vItem2: TItemOSInputDTO;
begin
  vDTO := TOrdemServicoInputDTO.Create;
  try
    vDTO.ClienteId := 1;
    vDTO.DescricaoProblema := 'Manutencao preventiva';

    vItem1 := TItemOSInputDTO.Create;
    vItem1.Descricao := 'Mao de obra especializada';
    vItem1.Quantidade := 2.0;
    vItem1.ValorUnitario := 150.00;
    vDTO.AdicionarItem(vItem1);

    vItem2 := TItemOSInputDTO.Create;
    vItem2.Descricao := 'Filtro de ar industrial';
    vItem2.Quantidade := 1.0;
    vItem2.ValorUnitario := 80.00;
    vDTO.AdicionarItem(vItem2);

    vDTO.Validar;
    AssertEquals('Total de itens deve ser 2', 2, vDTO.TotalItens);
  finally
    vDTO.Free;
  end;
end;

procedure TTestOrdemServicoService.TesteRejeitarOSSemItens;
var
  vDTO: TOrdemServicoInputDTO;
  vExcecaoLancada: Boolean;
begin
  vExcecaoLancada := False;
  vDTO := TOrdemServicoInputDTO.Create;
  try
    vDTO.ClienteId := 1;
    vDTO.DescricaoProblema := 'OS sem itens para teste';
    try
      vDTO.Validar;
    except
      on E: EValidationException do
        vExcecaoLancada := True;
    end;
    AssertTrue('Deve lancar EValidationException para OS sem itens', 
      vExcecaoLancada);
  finally
    vDTO.Free;
  end;
end;

initialization
  RegisterTest(TTestOrdemServicoService);

end.
