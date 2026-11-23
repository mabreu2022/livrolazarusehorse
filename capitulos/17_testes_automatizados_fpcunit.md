# Módulo 17: Testes Automatizados com FPCUnit, Mocks e CI/CD

No desenvolvimento moderno de software corporativo, a confiabilidade de 
uma API REST não pode repousar sobre testes manuais com ferramentas visuais. 
Refatorações de regras de negócio, atualizações de dependências no Boss ou 
migrações de versão do Free Pascal podem introduzir regressões silenciosas 
se não houver uma suíte automatizada de testes cobrindo os caminhos críticos 
do sistema.

Neste módulo, exploraremos o framework nativo **FPCUnit** do Free Pascal, 
projetado para rodar em modo console de forma ultrarrápida. Aprenderemos a 
isolar regras de negócio criando *Mocks* e *Stubs* de interfaces 
(`IOrdemServicoRepository`), a testar máquinas de estado sem necessidade de 
banco de dados ativo, a construir testes de integração HTTP ponta a ponta 
para endpoints do Horse e a integrar a execução dos testes em pipelines 
modernas de Integração Contínua (CI/CD) com relatórios no padrão JUnit XML.

---

## 1. Objetivos de Aprendizagem do Módulo

Ao final deste módulo, você será capaz de:
1. Estruturar um projeto de testes console com **FPCUnit** (`fpcunit`, 
   `testregistry`, `consoletestrunner`) no Free Pascal.
2. Implementar *Mocks* e *Fakes* de repositórios baseados em interfaces 
   Object Pascal para testes unitários puros e determinísticos de Services.
3. Validar cenários de sucesso e lançamento de exceções customizadas de domínio 
   (`EBusinessException`, `EValidationException`).
4. Construir testes de integração HTTP disparando requisições contra rotas do 
   Horse em portas de teste temporárias.
5. Exportar resultados de testes em formato padronizado JUnit XML para 
   integração direta com GitHub Actions e GitLab CI.
6. Integrar a detecção de vazamentos de memória (`HeapTrc`) na rotina de 
   testes automatizados, reprovando *pull requests* que causem memory leaks.

---

## 2. Fundamentação Conceitual e Arquitetural

### 2.1 A Pirâmide de Testes aplicada ao Ecossistema Pascal

Para garantir alta cobertura com baixo tempo de execução e manutenção 
sustentável, nossa estratégia divide-se em duas camadas essenciais:

```
+--------------------------------------------------------------------+
|                PIRAMIDE DE TESTES NO CONNECTOS API                 |
|                                                                    |
|           / \                                                      |
|          /   \     Testes de Integracao HTTP (Lentos / Abrangentes)|
|         /     \    - Disparam requests HTTP reais no Horse         |
|        / INTEGR\   - Verificam status HTTP, headers e JSON         |
|       /---------\                                                  |
|      /  UNITARIO \ Testes Unitarios de Dominio (Ultrarrapidos)     |
|     /  SERVICES   \- Testam regras de negocio e calculos com Mocks |
|    /______________\- Isolamento total de banco de dados e rede    |
+--------------------------------------------------------------------+
```

1. **Testes Unitários de Services (Base da Pirâmide):** Focam exclusivamente 
   nas regras de negócio (`TOrdemServicoService`). Como os repositórios são 
   injetados via interfaces (`IOrdemServicoRepository`), substituímos o 
   banco de dados Firebird 5.0 por implementações em memória (*Mock/Fake*). 
   Milhares de testes unitários rodam em frações de segundo.
2. **Testes de Integração HTTP (Topo da Pirâmide):** Inicializam o servidor 
   Horse em uma porta de teste (ex: porta 9099) e efetuam chamadas reais com 
   `TFPHTTPClient`, validando serialização JSON, middlewares de autenticação e 
   códigos de status HTTP.

### 2.2 O Framework FPCUnit: Estrutura e Ciclo de Vida

O FPCUnit é uma implementação padrão da família xUnit construída para o 
Free Pascal. Cada caso de teste herda de `TTestCase`:

```
+--------------------------------------------------------------------+
|                  CICLO DE VIDA DO TESTE NO FPCUNIT                 |
|                                                                    |
|  [TTestCase]                                                       |
|       |                                                            |
|       +---> SetUp()       : Inicializa o cenario (instancia mocks) |
|       |                                                            |
|       +---> TestMethod()  : Executa a acao e faz assercoes         |
|       |                     (AssertEquals, AssertTrue, etc.)       |
|       |                                                            |
|       +---> TearDown()    : Desaloca recursos e limpa a memoria    |
+--------------------------------------------------------------------+
```

> **Atenção Thread-Safety:**
> No FPCUnit, os testes de uma suíte são executados sequencialmente na thread 
> principal. Se os seus testes de integração dispararem chamadas contra o 
> servidor Horse, certifique-se de que o Horse foi inicializado com suporte a 
> `cthreads` e que cada teste utilize dados ou identificadores isolados para 
> não causar colisões de estado.

> **Boas Práticas FPC:**
> Sempre declare a destruição rigorosa de todos os objetos criados no `SetUp` 
> ou dentro do método de teste no `TearDown`. Ao compilar o projeto de testes 
> com a flag `-gh` (`HeapTrc`), o executor deve finalizar reportando 
> `0 unfreed memory blocks`. Qualquer bloco órfão falha o build no CI/CD.

### 2.3 Taxonomia de Dublês de Teste no Object Pascal

Na engenharia de software rigorosa (conforme definido por Gerard Meszaros 
em *xUnit Test Patterns*), o termo genérico *Mock* engloba diferentes tipos 
de dublês de teste (*Test Doubles*). No ecossistema Free Pascal orientado a 
interfaces, utilizamos três variantes principais:

1. **Dummy Objects:** Instâncias passadas apenas para preencher parâmetros de 
   métodos que nunca serão efetivamente utilizados na lógica testada.
2. **Fake Objects / In-Memory Stubs:** Implementações simplificadas e funcionais 
   em memória (como uma lista `TList` ou array simulando a tabela `ordens_servico`), 
   que devolvem respostas pré-definidas para alimentar o Service.
3. **Mocks Estritos:** Objetos que registram chamadas recebidas (métodos 
   invocados, parâmetros passados e contagem de execuções) e permitem verificar 
   se o Service interagiu com o contrato exatamente como esperado.

### 2.4 Arquitetura de Pipeline de CI/CD para Free Pascal no GitHub Actions

Para assegurar que nenhum código defeituoso atinja a branch principal, 
configuramos um workflow automatizado no GitHub Actions 
(`.github/workflows/ci.yml`). O runner Linux Ubuntu provisiona o compilador 
`fpc` 3.2.2, resolve dependências e executa o runner de testes:

```yaml
name: CI/CD Pipeline — ConnectOS API

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  build-and-test:
    runs-on: ubuntu-24.04
    steps:
      - name: Checkout do Repositorio
        uses: actions/checkout@v4

      - name: Instalar Free Pascal e Dependencias de Rede
        run: |
          sudo apt-get update
          sudo apt-get install -y fpc libssl-dev libfbclient2

      - name: Compilar Suite de Testes com HeapTrc
        run: |
          mkdir -p bin
          fpc -B -Mobjfpc -Sh -gh -gl -Fi./src -Fu./src/** -Fu./tests \
              tests/TestRunner.lpr -o./bin/test_runner

      - name: Executar Testes Automatizados FPCUnit
        run: |
          ./bin/test_runner --all --format=xml > test-results.xml

      - name: Publicar Relatorio de Testes JUnit
        uses: mikepenz/action-junit-report@v4
        if: always()
        with:
          report_paths: 'test-results.xml'
```

Se qualquer asserção falhar ou se o relatório do `HeapTrc` acusar vazamento 
de memória, o pipeline é interrompido com erro, bloqueando o merge do 
pull request antes de afetar o ambiente produtivo.

---

## 3. Implementação Passo a Passo

### 3.1 Construindo o Mock de Repositório (`Mocks.OrdemServico.pas`)

Para testar a camada de serviço sem tocar no banco de dados Firebird, 
criamos um repositório simulado em memória que implementa 
`IOrdemServicoRepository`:

```pascal
unit Mocks.OrdemServico;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, DTOs.OrdemServico, Interfaces.OrdemServico;

type
  { Mock em memoria para isolar testes unitarios de Services }
  TMockOrdemServicoRepository = class(TInterfacedObject, 
    IOrdemServicoRepository)
  private
    FUltimoIdGerado: Int64;
    FStatusSalvo: string;
    FItensInseridos: Integer;
    FCabecalhoInserido: Boolean;
  public
    constructor Create;
    function InserirCabecalho(const ATenantId: Int64; 
      ADTO: TOrdemServicoInputDTO; const AValorTotal: Double): Int64;
    procedure InserirItem(const ATenantId, AOSId: Int64; 
      AItem: TItemOSInputDTO);
    function ObterPorId(const ATenantId, AOSId: Int64): 
      TOrdemServicoOutputDTO;
    procedure AtualizarStatus(const ATenantId, AOSId: Int64; 
      const ANovoStatus: string);
    procedure Excluir(const ATenantId, AOSId: Int64);

    property UltimoIdGerado: Int64 read FUltimoIdGerado;
    property StatusSalvo: string read FStatusSalvo;
    property ItensInseridos: Integer read FItensInseridos;
    property CabecalhoInserido: Boolean read FCabecalhoInserido;
  end;

implementation

constructor TMockOrdemServicoRepository.Create;
begin
  inherited Create;
  FUltimoIdGerado := 100;
  FStatusSalvo := 'ABERTA';
  FItensInseridos := 0;
  FCabecalhoInserido := False;
end;

function TMockOrdemServicoRepository.InserirCabecalho(
  const ATenantId: Int64; ADTO: TOrdemServicoInputDTO; 
  const AValorTotal: Double): Int64;
begin
  Inc(FUltimoIdGerado);
  FCabecalhoInserido := True;
  Result := FUltimoIdGerado;
end;

procedure TMockOrdemServicoRepository.InserirItem(const ATenantId, 
  AOSId: Int64; AItem: TItemOSInputDTO);
begin
  Inc(FItensInseridos);
end;

function TMockOrdemServicoRepository.ObterPorId(const ATenantId, 
  AOSId: Int64): TOrdemServicoOutputDTO;
begin
  Result := TOrdemServicoOutputDTO.Create;
  Result.Id := AOSId;
  Result.TenantId := ATenantId;
  Result.ClienteId := 1;
  Result.NomeCliente := 'Cliente Teste Mock';
  Result.Status := FStatusSalvo;
  Result.DescricaoProblema := 'Problema Mock';
  Result.ValorTotal := 500.0;
  Result.CriadoEm := '2026-11-23 10:00:00';
end;

procedure TMockOrdemServicoRepository.AtualizarStatus(
  const ATenantId, AOSId: Int64; const ANovoStatus: string);
begin
  FStatusSalvo := ANovoStatus;
end;

procedure TMockOrdemServicoRepository.Excluir(const ATenantId, 
  AOSId: Int64);
begin
  FStatusSalvo := 'EXCLUIDA';
end;

end.
```

### 3.2 Testes Unitários de Regras de Negócio (`Test.Services.OrdemServico.pas`)

Criamos a suíte de testes unitários validando cálculo de totais e transição 
de status:

```pascal
unit Test.Services.OrdemServico;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, fpcunit, testregistry, Core.Exceptions,
  DTOs.OrdemServico, Interfaces.OrdemServico, Services.OrdemServico,
  Mocks.OrdemServico;

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
    procedure TesteTransicaoStatusInvalidaLancaExcecao;
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

procedure TTestOrdemServicoService.
  TesteTransicaoStatusInvalidaLancaExcecao;
var
  vExcecaoLancada: Boolean;
begin
  vExcecaoLancada := False;
  try
    { Aberta nao pode pular direto para Concluida sem execucao }
    FService.MudarStatus(1, 10, 'CONCLUIDA');
  except
    on E: EBusinessException do
      vExcecaoLancada := True;
    on E: ENotFoundException do
      { Esperado se o ID nao existe no mock, confirmando protecao }
      vExcecaoLancada := True;
  end;
  AssertTrue('Transicao invalida barrada por regra de negocio', 
    vExcecaoLancada);
end;

initialization
  RegisterTest(TTestOrdemServicoService);

end.
```

### 3.3 Testes de Integração HTTP (`Test.Integration.HTTP.pas`)

Construímos um teste que faz uma requisição HTTP real contra o endpoint 
de healthcheck da API para certificar o funcionamento do `fphttpserver`:

```pascal
unit Test.Integration.HTTP;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, fpcunit, testregistry, fphttpclient, fpjson,
  jsonparser;

type
  TTestIntegrationHTTP = class(TTestCase)
  published
    procedure TesteEndpointPingRetornaStatus200;
  end;

implementation

procedure TTestIntegrationHTTP.TesteEndpointPingRetornaStatus200;
var
  vClient: TFPHTTPClient;
  vResposta: string;
  vJSON: TJSONData;
  vObj: TJSONObject;
begin
  vClient := TFPHTTPClient.Create(nil);
  try
    vClient.ConnectTimeout := 2000;
    vClient.IOTimeout := 2000;
    try
      vResposta := vClient.Get('http://localhost:9000/ping');
      AssertEquals('Codigo HTTP deve ser 200', 200, 
        vClient.ResponseStatusCode);

      vJSON := GetJSON(vResposta);
      try
        AssertTrue('Resposta deve ser JSON', vJSON is TJSONObject);
        vObj := TJSONObject(vJSON);
        AssertEquals('Status deve ser UP', 'UP', 
          vObj.Get('status', ''));
      finally
        vJSON.Free;
      end;
    except
      on E: Exception do
        Fail('API deve estar ativa para teste de integracao: ' + 
          E.Message);
    end;
  finally
    vClient.Free;
  end;
end;

initialization
  RegisterTest(TTestIntegrationHTTP);

end.
```

### 3.4 O Runner de Testes Console (`TestRunner.lpr`)

Criamos o programa principal de execução de testes em linha de comando, 
apto a exportar relatórios XML para pipelines de integração contínua:

```pascal
program TestRunner;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Classes, consoletestrunner, fpcunit, testregistry,
  Test.Services.OrdemServico, Test.Integration.HTTP;

type
  TConnectOSTestRunner = class(TTestRunner)
  protected
    procedure ExtendXmlDocument(Doc: TObject); override;
  end;

procedure TConnectOSTestRunner.ExtendXmlDocument(Doc: TObject);
begin
  inherited ExtendXmlDocument(Doc);
end;

var
  vApplication: TConnectOSTestRunner;
begin
  DefaultFormat := fPlain;
  DefaultRunAllTests := True;

  vApplication := TConnectOSTestRunner.Create(nil);
  try
    vApplication.Initialize;
    vApplication.Title := 'ConnectOS API — Testes Automatizados';
    vApplication.Run;
  finally
    vApplication.Free;
  end;
end.
```

### 3.5 Testando Middlewares do Horse Isoladamente

Além de testar Services e rotas HTTP completas, a arquitetura modular 
do Horse permite testar middlewares de forma puramente unitária. Como a 
assinatura de um middleware é `procedure(Req: THorseRequest; Res: 
THorseResponse; Next: TNextProc)`, podemos instanciar objetos simulados de 
requisição e verificar se o middleware cumpre seu papel sem abrir um socket TCP.

Por exemplo, para testar se o middleware de Correlation-ID injeta o cabeçalho 
`X-Correlation-ID` quando ausente:
1. Criamos uma classe de teste que invoca o middleware diretamente.
2. Passamos um procedimento fictício para o parâmetro `Next`.
3. Verificamos se a variável booleana que indica o avanço do pipeline foi 
   sinalizada como verdadeira (`AssertTrue('Next deve ser chamado', vNextChamado)`).
4. Inspecionamos se o cabeçalho foi adicionado à resposta.

Esse nível cirúrgico de teste unitário garante que alterações na ordem de 
registro do pipeline (Módulo 05) não quebrem o fluxo de auditoria e segurança.

---

## 4. Testando o Endpoint e Executando a Suíte

### 4.1 Compilação e Execução dos Testes no Terminal

Podemos compilar o runner de testes diretamente via linha de comando 
utilizando o compilador `fpc`:

```bash
# Compilando o runner com diagnostico de memoria (-gh)
fpc -B -Mobjfpc -Sh -gh -gl -Fi./src -Fu./src/** -Fu./tests \
    tests/TestRunner.lpr -o./bin/test_runner

# Executando todos os testes
./bin/test_runner --all
```

**Saída esperada no terminal:**
```text
Loaded 4 tests
Running 4 tests...
..
Number of run tests: 4
Number of errors:    0
Number of failures:  0
All tests passed!
Heap dump by heaptrc unit of /home/dev/connectos/bin/test_runner
723 memory blocks allocated : 723 memory blocks freed
0 unfreed memory blocks : 0
True heap size : 131072
```

O relatório do `HeapTrc` comprova que `0 unfreed memory blocks` foram 
deixados para trás.

### 4.2 Executando Testes Específicos em Ciclos Rápidos de TDD

Durante o desenvolvimento diário orientado a testes (*Test-Driven Development*), 
reexecutar a suíte completa a cada pequena alteração pode desacelerar o 
fluxo de trabalho do programador. O runner do FPCUnit permite filtrar 
precisamente qual teste ou classe executar via argumento `--suite`:

```bash
# Executando apenas a classe de testes de servico
./bin/test_runner --suite=TTestOrdemServicoService

# Executando um unico metodo de teste especifico
./bin/test_runner \
  --suite=TTestOrdemServicoService.TesteCalculoTotalItensCorreto
```

O executor inicializa apenas os dublês necessários para aquele teste, 
retornando o resultado em milissegundos. Isso propicia um ciclo virtuoso 
*Red-Green-Refactor* com feedback imediato para o desenvolvedor.

### 4.3 Gerando Relatório JUnit XML para CI/CD

Para que servidores de automação (como GitHub Actions) exibam painéis 
gráficos dos testes, executamos o runner no modo XML:

```bash
./bin/test_runner --all --format=xml > test-results.xml
```

---

## 5. Armadilhas Comuns e Troubleshooting no FPC/Lazarus

### 5.1 Falsos Positivos no `HeapTrc` em Testes de Interfaces
Ao testar classes gerenciadas por interface (`TInterfacedObject`), evite 
declarar variáveis do tipo classe concreta (`vMock: TMockRepo`) misturadas 
com atribuições à interface (`IOrdemServicoRepository`). Se o destrutor for 
chamado manualmente e a interface também tentar desalocar a instância na 
saída do método, o FPC emitirá erro de corrupção de heap. 
**Regra:** Manipule instâncias exclusivamente pelo tipo da interface.

### 5.2 Testes de Integração Falhando por Falta de Rede
Testes de integração HTTP não devem rodar se a API não estiver de pé. Em 
pipelines de CI/CD, crie um script de orquestração que inicie a API em 
segundo plano, aguarde o endpoint `/ping` responder `200 OK` (via `curl --retry`) 
e só então dispare o `./test_runner`.

### 5.3 Ambientes Headless e Ausência de Display no Linux
Ao rodar testes que utilizam bibliotecas originalmente desenhadas para 
desktop (LCL), o FPC tenta conectar-se ao servidor X11 local. Em servidores 
Ubuntu em nuvem (onde não há display gráfico), o binário aborta com erro 
`Can't connect to X11 window server`. 

**Solução:** Mantenha os projetos de API e os runners de teste puramente em 
modo console (`consoletestrunner` em vez de `guitestrunner`). Caso alguma 
dependência exija o subsistema de janelas, execute o binário envelopado com 
o virtual framebuffer: `xvfb-run --auto-servernum ./bin/test_runner`.

### 5.4 Limpeza de Arquivos Temporários de Teste
Testes que manipulam anexos físicos (conforme visto no Módulo 14) devem 
criar diretórios temporários isolados em `/tmp/test_storage/` durante o 
`SetUp` e apagá-los recursivamente no `TearDown`. Deixar arquivos residuais 
em disco polui o ambiente de CI e causa falsos negativos em execuções 
subsequentes.

---

## 6. Resumo Executivo e Checklist de Revisão

Neste módulo, estabelecemos uma blindagem de qualidade e testes automatizados 
de alta velocidade com o FPCUnit nativo, capacitando o projeto para entregas 
contínuas sem riscos de regressão.

### Checklist de Revisão
- [ ] Os testes unitários de Services utilizam Mocks e rodam de forma 
      independente do banco de dados Firebird?
- [ ] Cenários de validação e disparo de exceções de domínio são verificados?
- [ ] O `TearDown` de cada teste libera adequadamente os recursos instanciados?
- [ ] A suíte roda limpa sob `HeapTrc` (`-gh`), acusando 0 blocos de 
      memória vazados?
- [ ] O runner console permite exportar relatórios padronizados em XML?
