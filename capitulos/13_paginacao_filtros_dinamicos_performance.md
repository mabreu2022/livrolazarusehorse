# Módulo 13: Paginação de Alta Performance, Filtros Dinâmicos e Metadados

Construir endpoints de listagem que escalam graciosamente com o crescimento 
da base de dados é um dos desafios mais críticos no desenvolvimento de APIs 
REST corporativas. Em sistemas de faturamento e ordens de serviço, tabelas 
facilmente acumulam milhões de registros. Uma consulta ingênua que retorne 
um volume irrestrito de dados pode saturar a memória RAM do servidor 
Lazarus, esgotar a banda da rede e congelar o banco de dados.

Neste módulo, exploraremos a sintaxe moderna de paginação introduzida no 
padrão SQL:2008 e refinada no **Firebird 5.0** (`OFFSET ... FETCH NEXT 
... ROWS ONLY`), comparando-a com os tradicionais comandos `FIRST/SKIP`. 
Construiremos um mecanismo robusto de filtros dinâmicos totalmente blindado 
contra SQL Injection, suporte a ordenação controlada via *whitelist* de 
colunas e um envelope JSON padronizado com metadados completos de navegação.

---

## 1. Objetivos de Aprendizagem do Módulo

Ao término deste módulo, o desenvolvedor será capaz de:
1. Implementar paginação eficiente utilizando as cláusulas padrão ANSI 
   `OFFSET ... FETCH NEXT ... ROWS ONLY` no Firebird 5.0.
2. Compreender a diferença arquitetural e de otimização de planos de execução 
   entre `FIRST/SKIP` e `OFFSET/FETCH`.
3. Construir um gerador dinâmico de cláusulas `WHERE` que utilize 
   exclusivamente parâmetros nomeados (`ParamByName`), impossibilitando 
   qualquer vetor de SQL Injection.
4. Implementar uma lista branca (*whitelist*) rigorosa para colunas de 
   ordenação (`ORDER BY`) e direções (`ASC` / `DESC`).
5. Estruturar envelopes JSON de resposta paginada com metadados universais: 
   `total_registros`, `total_paginas`, `pagina_atual`, `limite`, `tem_proxima` 
   e `tem_anterior`.
6. Otimizar índices compostos multi-tenant para que tanto a contagem 
   (`COUNT`) quanto a paginação sejam resolvidas via *Index Scan* rápido.

---

## 2. Fundamentação Conceitual e Arquitetural

### 2.1 Evolução da Paginação no Firebird: De `FIRST/SKIP` a `OFFSET/FETCH`

Historicamente, o Firebird utilizava as diretivas proprietárias `FIRST m 
SKIP n` posicionadas logo após o comando `SELECT`:

```sql
/* Sintaxe Legada (Firebird 2.x/3.x) */
SELECT FIRST 10 SKIP 20 o.id, o.valor_total
FROM ordens_servico o
ORDER BY o.id DESC;
```

A partir do Firebird 3.0 e consolidado como padrão de alta performance no 
**Firebird 5.0**, a engine adotou o padrão ANSI SQL:2008:

```sql
/* Sintaxe Padrao ANSI (Firebird 5.0) */
SELECT o.id, o.valor_total
FROM ordens_servico o
ORDER BY o.id DESC
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;
```

A nova sintaxe traz vantagens conceituais expressivas:
- **Compatibilidade Padronizada:** A consulta torna-se compatível com outros 
  grandes SGBDs (PostgreSQL, Oracle, SQL Server).
- **Semântica Posicional Clara:** As cláusulas de paginação residem no final 
  da consulta, facilitando a montagem dinâmica em código Pascal sem 
  necessidade de manipular o cabeçalho do `SELECT`.
- **Otimização no Firebird 5.0:** O otimizador de consultas avalia os índices 
  e evita a leitura física de linhas descartadas pelo `OFFSET` quando há um 
  índice ordenado compatível com o `ORDER BY`.

```
+--------------------------------------------------------------------+
|  FLUXO DE EXECUCAO DO OFFSET / FETCH NO FIREBIRD 5.0              |
|                                                                    |
|  1. Filtra por tenant_id e condicoes (Index Range Scan)            |
|  2. Percorre indice ordenado saltando n linhas (OFFSET n ROWS)     |
|  3. Recupera fisicamente apenas m registros (FETCH NEXT m ONLY)    |
|  4. Retorna cursor estrito sem alocar tabela inteira em memoria    |
+--------------------------------------------------------------------+
```

### 2.2 O Perigo Crítico de SQL Injection em Filtros Dinâmicos

Um erro frequente em aplicações comerciais é concatenar strings 
diretamente na cláusula `WHERE` para atender múltiplos filtros opcionais:

```pascal
{ CODIGO INSEGURO - NUNCA UTILIZE EM PRODUCAO }
vSQL := 'SELECT * FROM ordens_servico WHERE tenant_id = ' + vTenant;
if vStatus <> '' then
  vSQL := vSQL + ' AND status = ''' + vStatus + ''''; 
  { VULNERABILIDADE ACIMA! }
```

Se o parâmetro `vStatus` contiver a carga `' OR '1'='1`, a cláusula é 
corrompida e dados de outros tenants vazam na resposta.

> **Nota de Arquitetura:**
> **Parâmetros SQL são invioláveis.** Qualquer filtro dinâmico deve gerar 
> placeholders nomeados (ex: `:status`, `:cliente_id`) e injetar os 
> respectivos valores exclusivamente através da propriedade `ParamByName` 
> do `TSQLQuery`. Colunas e direções de ordenação, que não aceitam 
> parâmetros no SQL, devem ser validadas contra uma *whitelist* fixa.

### 2.3 Estrutura do Envelope JSON de Paginação

Para que frontends modernos (React, Vue, Angular, Mobile) renderizem tabelas 
e controles de paginação de forma consistente, a API deve padronizar o envelope:

```json
{
  "dados": [ { "id": 1 }, { "id": 2 } ],
  "paginacao": {
    "total_registros": 45,
    "total_paginas": 5,
    "pagina_atual": 1,
    "limite_por_pagina": 10,
    "tem_proxima_pagina": true,
    "tem_pagina_anterior": false
  }
}
```

---

## 3. Implementação Passo a Passo

### 3.1 DTOs de Paginação e Envelope de Resposta

Criaremos a unit `DTOs.Pagination.pas`, contendo os parâmetros de requisição 
e a estrutura genérica de metadados de saída:

```pascal
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
    FLimite := 100 { Teto maximo de seguranca }
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
    FCampoOrdenacao := 'id'; { Padrao seguro }

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
```

### 3.2 O Construtor Seguro de Consultas SQL (`Core.SQLBuilder.pas`)

Para garantir que toda cláusula `WHERE` e seus valores sejam 
completamente parametrizados, construímos um componente utilitário 
`TSQLFilterBuilder`:

```pascal
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
```

### 3.3 Repositório com Paginação no Firebird 5.0

Na camada de persistência, combinamos a contagem total com a seleção 
paginada usando `OFFSET ... FETCH NEXT ... ROWS ONLY`:

```pascal
unit Repositories.OrdemServicoPaginada;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, sqldb, fpjson, Core.ConnectionPool,
  Core.SQLBuilder, DTOs.Pagination, Interfaces.OrdemServico;

type
  { Extensao do repositorio de OS para consultas paginadas }
  TOrdemServicoPaginadaRepo = class
  private
    FUoW: IUnitOfWork;
  public
    constructor Create(AUoW: IUnitOfWork);
    function ContarTotal(const ATenantId: Int64; 
      ABuilder: TSQLFilterBuilder): Int64;
    function ListarPaginado(const ATenantId: Int64; 
      ABuilder: TSQLFilterBuilder; 
      AReq: TPaginationRequest): TJSONArray;
  end;

implementation

constructor TOrdemServicoPaginadaRepo.Create(AUoW: IUnitOfWork);
begin
  inherited Create;
  FUoW := AUoW;
end;

function TOrdemServicoPaginadaRepo.ContarTotal(const ATenantId: Int64; 
  ABuilder: TSQLFilterBuilder): Int64;
var
  vQry: TSQLQuery;
  vSQL: string;
begin
  Result := 0;
  vQry := TSQLQuery.Create(nil);
  try
    vQry.DataBase := FUoW.Wrapper.Connection;
    vQry.Transaction := FUoW.Wrapper.Transaction;

    vSQL := 'SELECT COUNT(*) AS total FROM ordens_servico' + 
      ABuilder.MontarClausulaWhere;
    vQry.SQL.Text := vSQL;
    ABuilder.AplicarParametros(vQry);
    vQry.Open;

    if not vQry.EOF then
      Result := vQry.FieldByName('total').AsLargeInt;
  finally
    vQry.Free;
  end;
end;

function TOrdemServicoPaginadaRepo.ListarPaginado(
  const ATenantId: Int64; ABuilder: TSQLFilterBuilder; 
  AReq: TPaginationRequest): TJSONArray;
var
  vQry: TSQLQuery;
  vSQL, vDirecao: string;
  vItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  vQry := TSQLQuery.Create(nil);
  try
    vQry.DataBase := FUoW.Wrapper.Connection;
    vQry.Transaction := FUoW.Wrapper.Transaction;

    if AReq.OrdemDescendente then
      vDirecao := 'DESC'
    else
      vDirecao := 'ASC';

    vSQL := 
      'SELECT o.id, o.cliente_id, c.nome AS nome_cliente, o.status, ' +
      '       o.valor_total, ' +
      '       CAST(o.criado_em AS VARCHAR(25)) AS criado_em ' +
      'FROM ordens_servico o ' +
      'INNER JOIN clientes c ON (c.id = o.cliente_id AND ' +
      '                          c.tenant_id = o.tenant_id)' +
      ABuilder.MontarClausulaWhere +
      Format(' ORDER BY o.%s %s ', [AReq.CampoOrdenacao, vDirecao]) +
      Format('OFFSET %d ROWS FETCH NEXT %d ROWS ONLY', 
        [AReq.Offset, AReq.Limite]);

    vQry.SQL.Text := vSQL;
    ABuilder.AplicarParametros(vQry);
    vQry.Open;

    while not vQry.EOF do
    begin
      vItem := TJSONObject.Create;
      vItem.Add('id', vQry.FieldByName('id').AsLargeInt);
      vItem.Add('cliente_id', 
        vQry.FieldByName('cliente_id').AsLargeInt);
      vItem.Add('nome_cliente', 
        vQry.FieldByName('nome_cliente').AsString);
      vItem.Add('status', vQry.FieldByName('status').AsString);
      vItem.Add('valor_total', vQry.FieldByName('valor_total').AsFloat);
      vItem.Add('criado_em', vQry.FieldByName('criado_em').AsString);
      Result.Add(vItem);
      vQry.Next;
    end;
  finally
    vQry.Free;
  end;
end;

end.
```

### 3.4 Controller Horse com Captura de Query String

Integramos a busca filtrada e paginada no Controller (`THorse`):

```pascal
unit Controllers.OrdemServicoPaginada;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, fpjson, Horse, DTOs.Pagination,
  Core.SQLBuilder, Interfaces.OrdemServico, Repositories.OrdemServico,
  Repositories.OrdemServicoPaginada;

type
  TOrdemServicoPaginadaController = class
  public
    class procedure RegistrarRotas;
    class procedure Listar(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
  end;

implementation

class procedure TOrdemServicoPaginadaController.RegistrarRotas;
begin
  THorse.Get('/api/v1/ordens-servico', @Listar);
end;

class procedure TOrdemServicoPaginadaController.Listar(
  Req: THorseRequest; Res: THorseResponse; Next: TNextProc);
var
  vTenantId: Int64;
  vReqPag: TPaginationRequest;
  vBuilder: TSQLFilterBuilder;
  vUoW: IUnitOfWork;
  vRepo: TOrdemServicoPaginadaRepo;
  vTotal: Int64;
  vDados: TJSONArray;
  vMeta: TPaginationMetadata;
  vEnvelope: TJSONObject;
  vCamposPermitidos: array of string;
begin
  vTenantId := Req.Session<Int64>('tenant_id');
  if vTenantId <= 0 then vTenantId := 1;

  vReqPag := TPaginationRequest.Create;
  try
    vReqPag.DefinirPaginacao(
      StrToIntDef(Req.Query['page'], 1),
      StrToIntDef(Req.Query['limit'], 10)
    );

    vCamposPermitidos := ['id', 'valor_total', 'status', 'criado_em'];
    vReqPag.DefinirOrdenacao(
      Req.Query['sort'],
      Req.Query['order'],
      vCamposPermitidos
    );

    vBuilder := TSQLFilterBuilder.Create;
    try
      { Filtro de tenant obrigatorio }
      vBuilder.AdicionarCondicao('o.tenant_id = :tenant_id');
      vBuilder.AdicionarFiltroInt64('o.tenant_id', 'tenant_id', 
        vTenantId);

      { Filtros opcionais seguros }
      if Req.Query.ContainsKey('status') then
        vBuilder.AdicionarFiltroTexto('o.status', 'status', 
          UpperCase(Req.Query['status']));

      if Req.Query.ContainsKey('cliente_id') then
        vBuilder.AdicionarFiltroInt64('o.cliente_id', 'cliente_id', 
          StrToInt64Def(Req.Query['cliente_id'], 0));

      vUoW := TUnitOfWork.Create;
      vRepo := TOrdemServicoPaginadaRepo.Create(vUoW);

      vTotal := vRepo.ContarTotal(vTenantId, vBuilder);
      vDados := vRepo.ListarPaginado(vTenantId, vBuilder, vReqPag);

      vMeta := TPaginationMetadata.Create(vTotal, vReqPag.Pagina, 
        vReqPag.Limite);
      try
        vEnvelope := TJSONObject.Create;
        vEnvelope.Add('dados', vDados);
        vEnvelope.Add('paginacao', vMeta.ToJSONObject);

        Res.Status(200).Send<TJSONObject>(vEnvelope);
      finally
        vMeta.Free;
      end;
    finally
      vBuilder.Free;
    end;
  finally
    vReqPag.Free;
  end;
end;

end.
```

---

## 4. Testando o Endpoint

Abaixo estão os testes práticos demonstrando o comportamento da API 
com paginação, filtros combinados e ordenação.

### 4.1 Consulta Simples com Paginação Padrão

```bash
curl -i -X GET \
  "http://localhost:9000/api/v1/ordens-servico?page=1&limit=2" \
  -H "Authorization: Bearer <SEU_JWT_AQUI>"
```

**Resposta esperada (`200 OK`):**
```json
{
  "dados": [
    {
      "id": 15,
      "cliente_id": 3,
      "nome_cliente": "Comercial Silva Eireli",
      "status": "ABERTA",
      "valor_total": 850.0,
      "criado_em": "2026-11-23 09:15:20"
    },
    {
      "id": 14,
      "cliente_id": 1,
      "nome_cliente": "Industrias ACME Ltda",
      "status": "EM_EXECUCAO",
      "valor_total": 420.0,
      "criado_em": "2026-11-23 08:40:10"
    }
  ],
  "paginacao": {
    "total_registros": 45,
    "total_paginas": 23,
    "pagina_atual": 1,
    "limite_por_pagina": 2,
    "tem_proxima_pagina": true,
    "tem_pagina_anterior": false
  }
}
```

### 4.2 Filtrando por Status e Ordenando por Valor Crescente

```bash
curl -i -X GET \
  "http://localhost:9000/api/v1/ordens-servico?status=ABERTA&page=1" \
  -H "Authorization: Bearer <SEU_JWT_AQUI>"
```

### 4.3 Teste de Tentativa de SQL Injection no Parâmetro Sort

Tentando injetar comando malicioso no parâmetro de ordenação:

```bash
curl -i -X GET \
  "http://localhost:9000/api/v1/ordens-servico?sort=id;DROP+TABLE;--" \
  -H "Authorization: Bearer <SEU_JWT_AQUI>"
```

**Comportamento Seguro Garantido:**
O método `DefinirOrdenacao` rejeita o valor desconhecido através da 
*whitelist* de campos autorizados e assume automaticamente a coluna 
padrão `id DESC`. O ataque é neutralizado sem gerar erro de sintaxe SQL 
e sem risco ao banco de dados.

---

## 5. Armadilhas Comuns e Troubleshooting no FPC/Lazarus

### 5.1 O Problema do "Deep Paging" (Páginas Muito Profundas)
Quando o cliente solicita `page=10000&limit=50`, a cláusula traduz-se em 
`OFFSET 500000 ROWS FETCH NEXT 50 ROWS ONLY`. Mesmo no Firebird 5.0, o 
banco precisa navegar por 500.000 entradas no índice antes de extrair as 
50 desejadas. 

**Mitigação:** 
1. Limite a navegação por offset a um teto máximo de páginas razoável 
   (ex: máximo de 100 páginas).
2. Para cenários de grande volume (exportações ou rolagem infinita), utilize 
   **Keyset Pagination** (ou Seek Method), filtrando pelo último ID visto: 
   `WHERE o.tenant_id = :t AND o.id < :ultimo_id ORDER BY o.id DESC ROWS 50`.

### 5.2 O Custo Excessivo de `COUNT(*)` em Tabelas Massivas
A execução de `SELECT COUNT(*)` para calcular `total_paginas` em tabelas com 
dezenas de milhões de linhas requer leitura de índice ou contagem de versões 
de registro no Firebird. 

**Soluções de Engenharia:**
- Crie um índice composto cobrindo exatamente os filtros: 
  `CREATE INDEX idx_os_filtro ON ordens_servico(tenant_id, status, id);`
- Em listagens muito pesadas, retorne metadados simplificados (apenas 
  `tem_proxima_pagina` buscando `FETCH NEXT :limite + 1`), evitando a 
  necessidade do `COUNT(*)` total.

### 5.3 Memory Leak ao Montar JSON Arrays Paginados
Ao iterar pelo `vQry` e adicionar `vItem := TJSONObject.Create` no `TJSONArray`, 
lembre-se que o array assume a posse do objeto adicionado. Nunca invoque 
`vItem.Free` após adicioná-lo ao `TJSONArray`. A destruição do array 
desaloca automaticamente todos os seus filhos.

---

## 6. Resumo Executivo e Checklist de Revisão

Neste módulo, elevamos a qualidade e a segurança das operações de listagem 
da nossa API Lazarus, implementando a sintaxe padrão ANSI `OFFSET/FETCH` do 
Firebird 5.0 e blindando o sistema contra ataques de SQL Injection.

### Checklist de Revisão
- [ ] A paginação utiliza `OFFSET ... ROWS FETCH NEXT ... ROWS ONLY` em 
      conformidade com o Firebird 5.0?
- [ ] Os parâmetros de ordenação passam por uma *whitelist* estrita de 
      colunas válidas, prevenindo injeções no `ORDER BY`?
- [ ] Todos os filtros dinâmicos utilizam exclusivamente parâmetros 
      nomeados com `ParamByName`?
- [ ] O limite por página (`limit`) possui um teto de segurança (ex: 100) 
      para evitar ataques de negação de serviço (DoS) por alocação excessiva?
- [ ] O envelope de resposta retorna metadados completos de navegação 
      (`total_registros`, `total_paginas`, `tem_proxima`, `tem_anterior`)?
- [ ] Os índices do Firebird 5.0 incluem `tenant_id` como primeira coluna 
      composta para acelerar tanto a filtragem quanto o `ORDER BY`?
