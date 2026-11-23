# MÓDULO 06: SERIALIZAÇÃO JSON DE ALTA PERFORMANCE COM FPJSON E JHONSON

---

## 1. OBJETIVOS DE APRENDIZAGEM DO MÓDULO

Ao final deste módulo, você será capaz de:

1. Dominar o ecossistema nativo de manipulação de dados JSON da biblioteca FCL do Free Pascal através das units **`fpjson`** e **`jsonparser`**.
2. Compreender a árvore de tipos polimórficos derivada de `TJSONData` (`TJSONObject`, `TJSONArray`, `TJSONString`, `TJSONIntegerNumber`, `TJSONFloatNumber` e `TJSONBoolean`).
3. Dominar com precisão cirúrgica a **regra de transferência de propriedade de memória (*ownership*)** em coleções JSON do FPC, prevenindo vazamentos (*memory leaks*) e violações catastróficas de liberação dupla (*double free*).
4. Integrar o middleware oficial **`horse-jhonson`**, automatizando a decodificação de corpos de requisição e a serialização de objetos de resposta com cabeçalhos `application/json` nativos.
5. Projetar Data Transfer Objects (**DTOs**) fortemente tipados em Object Pascal moderno (`{$mode objfpc}{$H+}`), implementando métodos bidirecionais de conversão de e para estruturas JSON.

---

## 2. FUNDAMENTAÇÃO CONCEITUAL E ARQUITETURAL

O formato **JSON (JavaScript Object Notation)**, normatizado pela especificação RFC 8259, consolidou-se como a linguagem franca de comunicação de dados na internet contemporânea. Toda API RESTful de alto nível precisa ser capaz de receber sequências brutas de bytes textuais em JSON, parseá-las rapidamente em estruturas de memória estruturadas, validar seus tipos e, após o processamento da regra de negócio, serializar as entidades de volta para texto compacto.

Em linguagens baseadas em Garbage Collection (como Java, C# ou JavaScript), a alocação e o descarte de objetos JSON ocorrem de forma invisível ao desenvolvedor, cobrando seu preço em pausas periódicas do coletor de lixo. No Free Pascal Compiler (FPC), onde desfrutamos da velocidade e previsibilidade da compilação nativa pura, o gerenciamento de memória é explícito e determinístico.

Para manipular JSON com performance máxima sem depender de gigantescas bibliotecas externas, o Free Pascal disponibiliza na Free Component Library (FCL) duas units essenciais:
- **`fpjson`:** Define o modelo orientado a objetos em memória para representar qualquer estrutura válida do padrão JSON.
- **`jsonparser`:** Implementa um analisador léxico e sintático de fluxo (*stream parser*) em código nativo, capaz de transformar strings UTF-8 em árvores de objetos com consumo mínimo de memória.

```
+-------------------------------------------------------------------+
|               HIERARQUIA POLIMÓRFICA DO FPJSON (FCL)              |
+-------------------------------------------------------------------+
                                  |
                             TJSONData (Base Abstrata)
                                  |
         +------------------------+------------------------+
         |                        |                        |
         v                        v                        v
    TJSONObject              TJSONArray              TJSONNumber
 (Dicionário chave:valor) (Lista indexada 0..N)   (Inteiros e Floats)
         |                        |                        |
         +------------------------+------------------------+
                                  |
         +------------------------+------------------------+
         |                                                 |
         v                                                 v
    TJSONString                                       TJSONBoolean
(Cadeias textuais UTF-8)                             (True / False)
```

### O Segredo de Engenharia: Transferência de Propriedade (Ownership)

A causa número um de travamentos (*crashes*), corrupção de heap e violações de acesso (*SIGSEGV*) em servidores web Pascal reside no desconhecimento da regra de propriedade de instâncias na unit `fpjson`.

Na biblioteca `fpjson`, quando você adiciona um objeto filho (como um `TJSONObject` ou `TJSONArray`) dentro de outro objeto ou array pai, **o elemento pai assume a posse (*ownership*) irrestrita daquele filho**.

Considere o seguinte exemplo:

```pascal
{ EXEMPLO DE TRANSFERÊNCIA DE POSSE }
var
  vPai: TJSONObject;
  vFilho: TJSONArray;
begin
  vPai := TJSONObject.Create;
  vFilho := TJSONArray.Create;

  { A partir desta linha, vPai torna-se o dono absoluto de vFilho }
  vPai.Add('itens', vFilho);

  { AO FINALIZAR: }
  vPai.Free; { <-- Destrói vPai E DESTROI AUTOMATICAMENTE vFilho! }
end;
```

Se o desenvolvedor — acreditando estar sendo zeloso com o gerenciamento de memória — tentar executar `vFilho.Free;` após ter executado `vPai.Add('itens', vFilho);` ou antes de `vPai.Free;`, ele causará o erro fatal de **Double Free (Liberação Dupla de Memória)**. Quando `vPai.Free` for invocado, ele tentará acessar e desalocar o ponteiro de `vFilho` que já foi liberado, corrompendo a tabela interna do Heap Manager do Free Pascal.

> **Atenção Thread-Safety:**  
> A regra de ouro no `fpjson` é estrita: **Quem adiciona um elemento complexo a um pai perde o direito de destruí-lo**. Apenas o objeto raiz (*root*) da árvore JSON deve ter seu método `.Free` explicitamente invocado pelo desenvolvedor, preferencialmente dentro de um bloco de proteção `try..finally`.

### O Papel do Middleware Jhonson (horse-jhonson)

Embora possamos utilizar `fpjson` e `jsonparser` manualmente em cada rota, escrever repetidamente rotinas de abertura de stream, parsing de `Req.Body`, instanciação de parser e blocos `try..finally` gera ruído de código desnecessário.

O middleware **`horse-jhonson`** atua como uma camada transparente de automação entre o Horse e o motor JSON:

1. **Decodificação de Entrada (Request):** Ao receber uma requisição com verbo de escrita (`POST`, `PUT`, `PATCH`), o Jhonson inspeciona se o cabeçalho `Content-Type` contém `application/json`. Em caso positivo, ele faz o parsing seguro da string do corpo para uma instância de `TJSONData`. O desenvolvedor pode então extrair o objeto tipado diretamente através da chamada genérica:
   ```pascal
   vJSON := Req.Body<TJSONObject>();
   ```
2. **Serialização de Saída (Response):** Quando a rota finaliza seu processamento e passa uma instância de `TJSONObject` ou `TJSONArray` para o método `Res.Send(vObjetoJSON)`, o Jhonson assume a posse daquele objeto, injeta o cabeçalho `Content-Type: application/json; charset=utf-8`, serializa os dados para texto e destrói automaticamente a instância do objeto JSON ao término do despacho de rede.
3. **Prevenção de Leaks:** Se a rota falhar ou o cliente abortar a conexão antes do envio, a infraestrutura do Jhonson garante a liberação determinística dos objetos alocados.

---

## 3. IMPLEMENTAÇÃO PASSO A PASSO

Construiremos agora uma camada profissional de serialização para o nosso projeto **ConnectOSApi**. Criaremos DTOs tipados para a entidade **Cliente** e refatoraremos nosso controlador para interagir nativamente com o middleware Jhonson.

### Passo 1: Instalando o Middleware Jhonson via Boss CLI

No terminal, acesse a pasta raiz do projeto prático (`codigo_fonte/connect_os_api/`) e instale a biblioteca oficial `horse-jhonson`:

```bash
cd codigo_fonte/connect_os_api
boss install github.com/HashLoad/jhonson
```

O Boss atualizará o manifesto `boss.json` e baixará os fontes para a pasta `modules/jhonson/`.

---

### Passo 2: Projetando o DTO Tipado: DTOs.Cliente.pas

Na Arquitetura Limpa, a camada de transporte de dados nunca deve trafegar instâncias cruas de banco de dados diretamente pela rede. Criamos **Data Transfer Objects (DTOs)** para definir contratos estritos de entrada e saída.

Crie o arquivo `src/DTOs/DTOs.Cliente.pas` com classes desacopladas contendo métodos canônicos `ToJSONObject` e `FromJSONObject`:

```pascal
{======================================================================}
{ Projeto: ConnectOSApi - API de Gestao e Faturamento Multi-Tenant     }
{ Unit   : DTOs.Cliente                                                }
{ Papel  : Data Transfer Objects para transporte de dados de Clientes  }
{======================================================================}
unit DTOs.Cliente;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  fpjson,
  jsonparser;

type
  { DTO de Saida: Dados enviados para o cliente externo }
  TClienteDTO = class
  private
    FId: Int64;
    FNomeRazao: string;
    FCPFCNPJ: string;
    FEmail: string;
    FTelefone: string;
    FAtivo: Boolean;
  public
    property Id: Int64 read FId write FId;
    property NomeRazao: string read FNomeRazao write FNomeRazao;
    property CPFCNPJ: string read FCPFCNPJ write FCPFCNPJ;
    property Email: string read FEmail write FEmail;
    property Telefone: string read FTelefone write FTelefone;
    property Ativo: Boolean read FAtivo write FAtivo;

    function ToJSONObject: TJSONObject;
    class function FromJSONObject(AJSON: TJSONObject): TClienteDTO;
  end;

  { DTO de Entrada: Dados recebidos para criacao ou atualizacao }
  TClienteInputDTO = class
  private
    FNomeRazao: string;
    FCPFCNPJ: string;
    FEmail: string;
    FTelefone: string;
  public
    property NomeRazao: string read FNomeRazao write FNomeRazao;
    property CPFCNPJ: string read FCPFCNPJ write FCPFCNPJ;
    property Email: string read FEmail write FEmail;
    property Telefone: string read FTelefone write FTelefone;

    class function FromJSONString(const AJSONStr: string): 
      TClienteInputDTO;
    class function FromJSONObject(AJSON: TJSONObject): 
      TClienteInputDTO;
  end;

implementation

{ TClienteDTO }

function TClienteDTO.ToJSONObject: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('id', FId);
  Result.Add('nome_razao', FNomeRazao);
  Result.Add('cpf_cnpj', FCPFCNPJ);
  Result.Add('email', FEmail);
  Result.Add('telefone', FTelefone);
  Result.Add('ativo', FAtivo);
end;

class function TClienteDTO.FromJSONObject(AJSON: TJSONObject): 
  TClienteDTO;
begin
  Result := TClienteDTO.Create;
  if not Assigned(AJSON) then
    Exit;

  Result.FId := AJSON.Get('id', Int64(0));
  Result.FNomeRazao := AJSON.Get('nome_razao', '');
  Result.FCPFCNPJ := AJSON.Get('cpf_cnpj', '');
  Result.FEmail := AJSON.Get('email', '');
  Result.FTelefone := AJSON.Get('telefone', '');
  Result.FAtivo := AJSON.Get('ativo', True);
end;

{ TClienteInputDTO }

class function TClienteInputDTO.FromJSONObject(AJSON: TJSONObject): 
  TClienteInputDTO;
begin
  Result := TClienteInputDTO.Create;
  if not Assigned(AJSON) then
    Exit;

  Result.FNomeRazao := Trim(AJSON.Get('nome_razao', ''));
  Result.FCPFCNPJ := Trim(AJSON.Get('cpf_cnpj', ''));
  Result.FEmail := Trim(AJSON.Get('email', ''));
  Result.FTelefone := Trim(AJSON.Get('telefone', ''));
end;

class function TClienteInputDTO.FromJSONString(
  const AJSONStr: string): TClienteInputDTO;
var
  vParser: TJSONParser;
  vJSONData: TJSONData;
begin
  Result := nil;
  if Trim(AJSONStr) = '' then
    Exit;

  vParser := TJSONParser.Create(AJSONStr, [joUTF8]);
  try
    try
      vJSONData := vParser.Parse;
      if Assigned(vJSONData) and (vJSONData is TJSONObject) then
      begin
        Result := FromJSONObject(TJSONObject(vJSONData));
        vJSONData.Free;
      end;
    except
      { Se o JSON for malformado, retorna nil defensivamente }
      Result := nil;
    end;
  finally
    vParser.Free;
  end;
end;

end.
```

> **Boas Práticas FPC:**  
> Ao construir métodos de extração em `TJSONObject`, utilize sempre as sobrecargas seguras `AJSON.Get('campo', ValorPadrao)`. Métodos diretos como `AJSON.Strings['campo']` lançam a exceção `EJSON` caso a propriedade não exista no documento recebido, interrompendo o processamento. O método `Get` fornece um valor padrão caso o campo seja omitido, tornando o código defensivo contra contratos incompletos.

---

### Passo 3: Refatorando o Controlador com Jhonson e DTOs

Agora integraremos os DTOs e a serialização automatizada em `src/Controllers/Controllers.Clientes.pas`. Observe como o código torna-se limpo e legível:

```pascal
unit Controllers.Clientes;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  fpjson,
  Horse,
  Core.ProblemDetails,
  DTOs.Cliente;

type
  TControllersClientes = class
  private
    class procedure Listar(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
    class procedure ObterPorId(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
    class procedure Criar(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
    class procedure Excluir(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
  public
    class procedure Registry;
  end;

implementation

{ TControllersClientes }

class procedure TControllersClientes.Listar(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vEnvelope: TJSONObject;
  vListaItens: TJSONArray;
  vDTO1, vDTO2: TClienteDTO;
begin
  { Montagem do envelope de resposta paginada com TJSONObject }
  vEnvelope := TJSONObject.Create;
  vListaItens := TJSONArray.Create;

  { Cria DTO 1 }
  vDTO1 := TClienteDTO.Create;
  try
    vDTO1.Id := 101;
    vDTO1.NomeRazao := 'Conect Solutions TI LTDA';
    vDTO1.CPFCNPJ := '12345678000199';
    vDTO1.Email := 'contato@conectsolutions.com';
    vDTO1.Telefone := '(11) 98888-7777';
    vDTO1.Ativo := True;
    vListaItens.Add(vDTO1.ToJSONObject);
  finally
    vDTO1.Free;
  end;

  { Cria DTO 2 }
  vDTO2 := TClienteDTO.Create;
  try
    vDTO2.Id := 102;
    vDTO2.NomeRazao := 'Mecanica Brasil Express';
    vDTO2.CPFCNPJ := '98765432000100';
    vDTO2.Email := 'atendimento@mecanicabrasil.com';
    vDTO2.Telefone := '(11) 97777-6666';
    vDTO2.Ativo := True;
    vListaItens.Add(vDTO2.ToJSONObject);
  finally
    vDTO2.Free;
  end;

  { Adiciona array: vEnvelope assume a posse de vListaItens }
  vEnvelope.Add('total', 2);
  vEnvelope.Add('pagina', 1);
  vEnvelope.Add('dados', vListaItens);

  { O Horse/Jhonson assume posse de vEnvelope e o desaloca }
  Res.Send(vEnvelope)
     .Status(THTTPStatus.OK);
end;

class procedure TControllersClientes.ObterPorId(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vClienteId: Int64;
  vDTO: TClienteDTO;
begin
  vClienteId := StrToInt64Def(Req.Params.Field('id').AsString, 0);

  if vClienteId <= 0 then
  begin
    TProblemDetails.CreateNew
      .SetType('https://api.connectos.com/erros/parametro-invalido')
      .SetTitle('Parametro Invalido')
      .SetStatus(400)
      .SetDetail('O ID do cliente deve ser um numero valido.')
      .SendTo(Res);
    Exit;
  end;

  if vClienteId = 404 then
  begin
    TProblemDetails.CreateNew
      .SetType('https://api.connectos.com/erros/recurso-inexistente')
      .SetTitle('Cliente Nao Localizado')
      .SetStatus(404)
      .SetDetail('Cliente nao cadastrado.')
      .SendTo(Res);
    Exit;
  end;

  vDTO := TClienteDTO.Create;
  try
    vDTO.Id := vClienteId;
    vDTO.NomeRazao := 'Cliente Localizado via DTO';
    vDTO.CPFCNPJ := '55444333000122';
    vDTO.Email := 'financeiro@clientedto.com.br';
    vDTO.Telefone := '(11) 3333-2222';
    vDTO.Ativo := True;

    Res.Send(vDTO.ToJSONObject)
       .Status(THTTPStatus.OK);
  finally
    vDTO.Free;
  end;
end;

class procedure TControllersClientes.Criar(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vInputJSON: TJSONObject;
  vInputDTO: TClienteInputDTO;
  vResposta: TJSONObject;
begin
  { Extrai o TJSONObject do corpo da requisicao via Jhonson }
  vInputJSON := Req.Body<TJSONObject>();

  if not Assigned(vInputJSON) then
  begin
    TProblemDetails.CreateNew
      .SetType('https://api.connectos.com/erros/json-invalido')
      .SetTitle('Payload Invalido')
      .SetStatus(400)
      .SetDetail('O corpo da requisicao deve ser um JSON valido.')
      .SendTo(Res);
    Exit;
  end;

  vInputDTO := TClienteInputDTO.FromJSONObject(vInputJSON);
  try
    { Validacoes de regras de negocio essenciais }
    if vInputDTO.NomeRazao = '' then
    begin
      TProblemDetails.CreateNew
        .SetType('https://api.connectos.com/erros/validacao-campos')
        .SetTitle('Violacao de Dados')
        .SetStatus(422)
        .SetDetail('A razao social nao pode ser vazia.')
        .AddInvalidParam('nome_razao', 'Campo mandatorio')
        .SendTo(Res);
      Exit;
    end;

    { Monta objeto JSON de retorno }
    vResposta := TJSONObject.Create;
    vResposta.Add('id', Int64(450));
    vResposta.Add('nome_razao', vInputDTO.NomeRazao);
    vResposta.Add('mensagem', 'Cadastrado com sucesso via DTO/Jhonson');

    Res.RawWebResponse.SetCustomHeader('Location', 
      '/api/v1/clientes/450');

    Res.Send(vResposta)
       .Status(THTTPStatus.Created);
  finally
    vInputDTO.Free;
  end;
end;

class procedure TControllersClientes.Excluir(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vClienteId: Int64;
begin
  vClienteId := StrToInt64Def(Req.Params.Field('id').AsString, 0);
  if vClienteId <= 0 then
  begin
    TProblemDetails.CreateNew
      .SetType('https://api.connectos.com/erros/parametro-invalido')
      .SetTitle('Parametro Invalido')
      .SetStatus(400)
      .SetDetail('Identificador numerico esperado.')
      .SendTo(Res);
    Exit;
  end;

  Res.Status(THTTPStatus.NoContent);
end;

class procedure TControllersClientes.Registry;
begin
  THorse.Get('/api/v1/clientes', @Listar);
  THorse.Get('/api/v1/clientes/:id', @ObterPorId);
  THorse.Post('/api/v1/clientes', @Criar);
  THorse.Delete('/api/v1/clientes/:id', @Excluir);
end;

end.
```

---

### Passo 4: Conectando o Middleware Jhonson no ConnectOSApi.lpr

Adicione a unit `Horse.Jhonson` na cláusula `uses` e registre `THorse.Use(Jhonson);` no início da pilha de execução:

```pascal
program ConnectOSApi;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  SysUtils,
  Classes,
  Horse,
  Horse.Jhonson,
  Horse.Provider.FPHTTP,
  Middlewares.CorrelationId,
  Middlewares.Logger,
  Middlewares.RateLimit,
  Controllers.Ping,
  Controllers.Clientes;

procedure DoOnListen;
begin
  WriteLn('----------------------------------------------------');
  WriteLn('  CONNECT OS API - SERIALIZACAO JHONSON ATIVA       ');
  WriteLn('  Compilador       : Free Pascal ' + {$I %FPCVERSION%});
  WriteLn('  Ouvindo em : http://0.0.0.0:' + IntToStr(THorse.Port));
  WriteLn('----------------------------------------------------');
end;

var
  vPorta: Word;
begin
  vPorta := StrToIntDef(GetEnvironmentVariable('PORT'), 9000);
  THorse.Port := vPorta;

  { REGISTRO DO MIDDLEWARE DE SERIALIZACAO JSON }
  THorse.Use(Jhonson);

  { PIPELINE DE AUDITORIA E RESILIENCIA }
  THorse.Use(@TMiddlewareCorrelationId.Middleware);
  THorse.Use(@TMiddlewareLogger.Middleware);
  THorse.Use(@TMiddlewareRateLimit.Middleware);

  { REGISTRO DE ROTAS }
  TControllersPing.Registry;
  TControllersClientes.Registry;

  THorse.Listen(@DoOnListen);
end.
```

---

## 4. TESTANDO O ENDPOINT

Vamos testar a serialização automática de saída e a decodificação estruturada de entrada utilizando o `curl`.

### Teste 1: Listagem com Envelope Paginado e Array JSON (GET)

Execute uma requisição `GET` para a rota `/api/v1/clientes`:

```bash
curl -i http://localhost:9000/api/v1/clientes
```

**Resposta Formatada com Cabeçalho Automático application/json:**

```http
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8
Content-Length: 298
Date: Mon, 23 Nov 2026 12:05:00 GMT
Server: fphttpserver

{"total":2,"pagina":1,"dados":[
  {"id":101,"nome_razao":"Conect Solutions TI LTDA",
   "cpf_cnpj":"12345678000199","email":"contato@conectsolutions.com",
   "telefone":"(11) 98888-7777","ativo":true},
  {"id":102,"nome_razao":"Mecanica Brasil Express",
   "cpf_cnpj":"98765432000100","email":"atendimento@mecanicabrasil.com",
   "telefone":"(11) 97777-6666","ativo":true}
]}
```

Observe que o middleware Jhonson automaticamente formatou a árvore `vEnvelope`, aplicou o charset UTF-8 correto e calculou com exatidão o `Content-Length`.

---

### Teste 2: Cadastro de Cliente Enviando Payload JSON Estruturado (POST)

Envie uma requisição `POST` com um payload formatado:

```bash
curl -i -X POST http://localhost:9000/api/v1/clientes \
     -H "Content-Type: application/json" \
     -d '{"nome_razao":"Transportadora TransNorte",
          "cpf_cnpj":"77888999000155",
          "email":"contato@transnorte.com.br"}'
```

**Resposta do Servidor (201 Created com DTO Serializado):**

```http
HTTP/1.1 201 Created
Location: /api/v1/clientes/450
Content-Type: application/json; charset=utf-8
Content-Length: 95

{"id":450,"nome_razao":"Transportadora TransNorte",
 "mensagem":"Cadastrado com sucesso via DTO/Jhonson"}
```

O Horse extraiu o objeto via `Req.Body<TJSONObject>()`, populou o DTO `TClienteInputDTO`, validou os campos e emitiu a resposta tipada sem que nenhuma linha de parsing manual precisasse ser escrita.

---

### Teste 3: Rejeição de JSON Sintaticamente Malformado

Envie um JSON deliberadamente quebrado (sem fechar a chave):

```bash
curl -i -X POST http://localhost:9000/api/v1/clientes \
     -H "Content-Type: application/json" \
     -d '{"nome_razao":"Incompleto"'
```

**Resposta do Servidor (Rejeição com 400 Bad Request):**

```http
HTTP/1.1 400 Bad Request
Content-Type: application/problem+json; charset=utf-8
Content-Length: 218

{"type":"https://api.connectos.com/erros/json-invalido",
 "title":"Payload Invalido",
 "status":400,
 "detail":"O corpo da requisicao deve ser um JSON valido.",
 "instance":"/api/v1/clientes"}
```

---

## 5. ARMADILHAS COMUNS E TROUBLESHOOTING NO FPC/LAZARUS

---

### Armadilha 1: Falha Catastrófica por Double Free no fpjson

**Sintoma:** O servidor funciona para a primeira requisição, mas trava subitamente ou emite o erro `Heap dump: Invalid pointer operation` ao final da execução.

**Causa Raiz:** Você criou um `TJSONArray`, adicionou-o a um `TJSONObject` via `vObjeto.Add('dados', vArray)` e, no final do procedimento, executou `vArray.Free;`.

**Solução:** Lembre-se: `vObjeto.Add` transfere a propriedade de `vArray`. Destrua **apenas** o objeto de nível superior mais externo.

---

### Armadilha 2: Esquecer de Registrar o Jhonson ANTES dos Middlewares de Rota

**Sintoma:** Ao tentar chamar `Req.Body<TJSONObject>()` dentro de um controlador, a função retorna `nil` mesmo quando o cliente enviou um JSON perfeitamente válido.

**Causa Raiz:** O middleware `Jhonson` não foi registrado no arquivo `.lpr` ou foi registrado **após** a chamada `THorse.Listen` ou após a rota.

**Solução:** Posicione `THorse.Use(Jhonson);` como a primeiríssima linha de registro de middlewares no programa principal.

---

### Armadilha 3: Formatação Numérica com Vírgula Decimal em Floats

**Sintoma:** Ao serializar valores monetários ou de ponto flutuante no FPC (ex: `1250.50`), o JSON gerado contém `"valor": 1250,50` (com vírgula), tornando o JSON inválido segundo a RFC 8259!

**Causa Raiz:** O Free Pascal adota as configurações regionais do sistema operacional hospedeiro (`FormatSettings.DecimalSeparator`). Em servidores configurados com o idioma `pt_BR`, o separador decimal padrão é a vírgula.

**Solução:** O `fpjson` trata isso internamente na maioria das operações, mas ao converter strings numéricas manualmente, force sempre o separador decimal padrão da internet (ponto `.`):

```pascal
FormatSettings.DecimalSeparator := '.';
```

---

## 6. RESUMO EXECUTIVO E CHECKLIST DE REVISÃO

### Tabela Comparativa de Métodos fpjson

| Operação | Método Recomendado | Cuidado Crítico de Memória |
| :--- | :--- | :--- |
| **Criar Objeto** | `TJSONObject.Create` | Deve ser liberado ou assumido pelo Horse. |
| **Criar Array** | `TJSONArray.Create` | Ao adicionar ao objeto pai, não libere manualmente.|
| **Leitura Segura** | `AJSON.Get('chave', Padrao)` | Evita exceções `EJSON` se a chave não existir. |
| **Parsing Manual** | `TJSONParser.Create(Str, [joUTF8])` | O parser deve ser destruído em `try..finally`. |
| **Envio no Horse** | `Res.Send(vJSONObject)` | Jhonson assume a posse e destrói automaticamente. |

---

### Checklist de Revisão e Auditoria Técnica

Antes de avançar para o Módulo 07, certifique-se de validar os seguintes itens:

- [ ] **Instalação do Jhonson:** O middleware `horse-jhonson` foi instalado via Boss e consta na pasta `modules/jhonson`.
- [ ] **Posicionamento do Middleware:** A instrução `THorse.Use(Jhonson);` é executada antes dos outros middlewares e das rotas.
- [ ] **Isolamento via DTO:** As entradas e saídas utilizam classes dedicadas em `src/DTOs/DTOs.Cliente.pas`.
- [ ] **Mime Type Automático:** As respostas enviadas via `Res.Send(TJSONObject)` emitem `Content-Type: application/json; charset=utf-8`.
- [ ] **Zero Vazamentos de Memória:** Nenhum elemento filho pertencente a um `TJSONObject` é liberado manualmente, prevenindo erros de *double free*.

Com a serialização JSON plenamente dominada, avançamos agora para o **Módulo 07**, onde aprenderemos a configurar o controle de origens cruzadas (**CORS**) e a construir um interceptador global de exceções para proteger a API contra vazamento de informações sensíveis.
