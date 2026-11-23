# Módulo 16: Documentação Viva com OpenAPI 3.0 e Swagger UI Embarcado

Uma API de alto padrão de engenharia não é medida apenas pela velocidade 
de resposta ou pela sofisticação de sua arquitetura limpa, mas também 
pela clareza e precisão de seus contratos com os desenvolvedores que a 
consomem. Em equipes modernas de engenharia, onde frontends web, aplicativos 
mobile e sistemas parceiros integram-se simultaneamente ao mesmo backend, 
manter a documentação técnica atualizada e interativa é fundamental.

Neste módulo, implementaremos o padrão **OpenAPI 3.0** diretamente no 
nosso ecossistema Horse e Lazarus. Aprenderemos a gerar a especificação 
em formato JSON de forma programática utilizando o `fpjson` nativo, a 
documentar esquemas de segurança (Bearer JWT), parâmetros de rota/query e 
estruturas de erro padronizadas pela RFC 7807, e a servir uma interface 
interativa do **Swagger UI** embarcada diretamente pelo servidor nativo 
Free Pascal, sem qualquer dependência externa de Node.js ou Apache/Nginx.

---

## 1. Objetivos de Aprendizagem do Módulo

Ao final deste módulo, você será capaz de:
1. Compreender a anatomia completa da especificação OpenAPI 3.0 (`openapi`, 
   `info`, `paths`, `components/schemas` e `securitySchemes`).
2. Projetar um gerador programático de especificações OpenAPI utilizando as 
   classes nativas `TJSONObject` e `TJSONArray` do `fpjson`.
3. Documentar contratos detalhados para endpoints de cadastro, ordens de 
   serviço, anexos e autenticação com JWT.
4. Servir a interface interativa do Swagger UI diretamente pelo `fphttpserver` 
   do Horse na rota `/api/docs`.
5. Proteger ambientes de produção contra exposição indevida da documentação 
   através de flags de ambiente e middlewares de autorização.
6. Habilitar a funcionalidade *Try it out* com suporte nativo a tokens Bearer, 
   permitindo testes em tempo real de endpoints autenticados.

---

## 2. Fundamentação Conceitual e Arquitetural

### 2.1 A Especificação OpenAPI 3.0

O OpenAPI Specification (OAS) é o padrão universal agnóstico a linguagens 
para descrição de APIs RESTful. Um documento OpenAPI 3.0 divide-se em seções 
bem delimitadas:

```
+--------------------------------------------------------------------+
|               ESTRUTURA DO DOCUMENTO OPENAPI 3.0                   |
|                                                                    |
|  1. openapi: "3.0.3" (Versao da especificacao)                     |
|  2. info: Metadados (titulo, versao, descricao, contato)           |
|  3. servers: Lista de URLs base da API (dev, homolog, producao)    |
|  4. paths: Mapeamento de rotas (/api/v1/...), verbos, params,      |
|     requestBody e responses (200, 201, 400, 401, 422)              |
|  5. components:                                                    |
|     - schemas: DTOs e entidades (Cliente, OrdemServico, Problem)   |
|     - securitySchemes: Definicao de seguranca (Bearer JWT, API-Key)|
|  6. security: Requisitos globais ou locais de autenticacao         |
+--------------------------------------------------------------------+
```

### 2.2 Swagger UI Embarcado vs. Servidor Separado

Tradicionalmente, muitas equipes hospedam o Swagger UI em contêineres 
separados com Node.js ou em servidores Nginx dedicados. Contudo, no 
desenvolvimento de micro-APIs e ferramentas corporativas com Free Pascal, 
embarcar a interface HTML diretamente no binário da aplicação traz enormes 
benefícios operacionais:
- **Zero Configuração Extra:** Um único arquivo executável estático (`connect_os_api`) 
  roda a API e entrega sua documentação completa.
- **Sincronia Absoluta:** Como a rota `/api/docs/openapi.json` é gerada pelo 
  próprio código compilado, a documentação reflete exatamente a versão da 
  aplicação em execução.
- **Portabilidade:** Ideal para ambientes de contêineres enxutos (Docker Alpine 
  ou Debian Minimal), sem sobrecarga de runtimes externos.

```
+--------------------------------------------------------------------+
|              ARQUITETURA DO SWAGGER EMBARCADO NO HORSE             |
|                                                                    |
|  [Navegador / Dev]                                                 |
|         |                                                          |
|         +---> GET /api/docs ---------------> [HTML Swagger UI]     |
|         |                                         |                |
|         |                                    Carrega Assets        |
|         |                                    via CDN Oficial       |
|         v                                         v                |
|  [Navegador] <--- GET /api/docs/openapi.json <----+                |
|                                                                    |
|  [API Horse / FPC]:                                                |
|  - Rota 1: /api/docs              (Retorna HTML com CDN)           |
|  - Rota 2: /api/docs/openapi.json (Gera TJSONObject da API)        |
+--------------------------------------------------------------------+
```

> **Nota de Arquitetura:**
> Em servidores de produção com alta restrição de segurança, a rota 
> `/api/docs` deve ser desabilitada ou restrita a redes internas via 
> variáveis de ambiente (`SWAGGER_ENABLED=false`), prevenindo que agentes 
> mal-intencionados descubram parâmetros de rotas e estruturas internas.

### 2.3 RTTI e Metaprogramação no FPC vs Abordagem Programática Direta

Em ecossistemas como C# (.NET) ou Java (Spring), frameworks geram a 
especificação OpenAPI inspecionando anotações e reflexão em tempo de 
execução (*Reflection/RTTI*). No ecossistema Free Pascal / Lazarus, 
contudo, o compilador FPC historicamente possui um modelo de RTTI estendido 
que difere significativamente do Delphi moderno. 

Tentativas de utilizar bibliotecas baseadas em atributos complexos no FPC 
frequentemente esbarram em problemas de compilação cruzada para Linux x86_64, 
aumento desmedido do tamanho do executável e lentidão na inicialização da API.

Por essa razão, adotamos a **Abordagem Programática Estruturada**:
1. Construímos a especificação utilizando árvores de `TJSONObject` e `TJSONArray` 
   do `fpjson` nativo.
2. A montagem do JSON ocorre em milissegundos e possui custo zero de reflexão.
3. Compatibilidade garantida em 100% dos alvos de compilação (Windows, Linux, 
   ARM64, Docker).
4. Possibilidade de ler metadados dinamicamente de arquivos de configuração, 
   variáveis de ambiente ou banco de dados.

### 2.4 Versionamento de Contratos de API (v1 e v2) com OpenAPI

Ao evoluir uma API comercial, mudanças disruptivas (*breaking changes*) 
exigem a publicação de uma nova versão (ex: `/api/v2`). No Swagger, podemos 
servir múltiplos documentos simultaneamente utilizando o seletor de *URLs*:

```json
{
  "urls": [
    { "name": "V1 — Estavel", "url": "/api/docs/v1/openapi.json" },
    { "name": "V2 — Nova Versao", "url": "/api/docs/v2/openapi.json" }
  ]
}
```

O Swagger UI renderiza uma caixa de seleção (*dropdown*) no topo da página, 
permitindo que desenvolvedores alternem instantaneamente entre as 
especificações sem trocar de ambiente ou recarregar a interface.

---

## 3. Implementação Passo a Passo

### 3.1 Construindo o Documento OpenAPI com `fpjson`

Criaremos a unit `Core.OpenAPI.pas`, responsável por instanciar a árvore 
de nós da especificação OpenAPI 3.0:

```pascal
unit Core.OpenAPI;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, fpjson;

type
  TOpenAPIGenerator = class
  private
    class function CriarInfo: TJSONObject; static;
    class function CriarSecuritySchemes: TJSONObject; static;
    class function CriarSchemas: TJSONObject; static;
    class function CriarPaths: TJSONObject; static;
  public
    class function GerarEspecificacao: TJSONObject; static;
  end;

implementation

class function TOpenAPIGenerator.CriarInfo: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('title', 'ConnectOS API — Gestao de OS e Faturamento');
  Result.Add('description', 
    'API REST desenvolvida em Free Pascal e Lazarus');
  Result.Add('version', '1.0.0');
end;

class function TOpenAPIGenerator.CriarSecuritySchemes: TJSONObject;
var
  vBearer: TJSONObject;
begin
  Result := TJSONObject.Create;
  vBearer := TJSONObject.Create;
  vBearer.Add('type', 'http');
  vBearer.Add('scheme', 'bearer');
  vBearer.Add('bearerFormat', 'JWT');
  vBearer.Add('description', 
    'Insira o token JWT no formato: Bearer <token>');
  Result.Add('bearerAuth', vBearer);
end;

class function TOpenAPIGenerator.CriarSchemas: TJSONObject;
var
  vCliente, vPropsCli, vOS, vPropsOS, vProblem, vPropsProb: TJSONObject;
begin
  Result := TJSONObject.Create;

  { Schema de Cliente }
  vCliente := TJSONObject.Create;
  vCliente.Add('type', 'object');
  vPropsCli := TJSONObject.Create;
  vPropsCli.Add('id', TJSONObject.Create(['type', 'integer']));
  vPropsCli.Add('nome', TJSONObject.Create(['type', 'string']));
  vPropsCli.Add('cpf_cnpj', TJSONObject.Create(['type', 'string']));
  vCliente.Add('properties', vPropsCli);
  Result.Add('Cliente', vCliente);

  { Schema de Ordem de Servico }
  vOS := TJSONObject.Create;
  vOS.Add('type', 'object');
  vPropsOS := TJSONObject.Create;
  vPropsOS.Add('id', TJSONObject.Create(['type', 'integer']));
  vPropsOS.Add('status', TJSONObject.Create(['type', 'string']));
  vPropsOS.Add('valor_total', TJSONObject.Create(['type', 'number']));
  vOS.Add('properties', vPropsOS);
  Result.Add('OrdemServico', vOS);

  { Schema RFC 7807 Problem Details }
  vProblem := TJSONObject.Create;
  vProblem.Add('type', 'object');
  vPropsProb := TJSONObject.Create;
  vPropsProb.Add('type', TJSONObject.Create(['type', 'string']));
  vPropsProb.Add('title', TJSONObject.Create(['type', 'string']));
  vPropsProb.Add('status', TJSONObject.Create(['type', 'integer']));
  vPropsProb.Add('detail', TJSONObject.Create(['type', 'string']));
  vProblem.Add('properties', vPropsProb);
  Result.Add('ProblemDetails', vProblem);
end;

class function TOpenAPIGenerator.CriarPaths: TJSONObject;
var
  vPathOS, vGetOS, vResp200, vContJSON, vSchemaRef: TJSONObject;
  vResponses, vSecurityArr: TJSONArray;
  vSecItem: TJSONObject;
begin
  Result := TJSONObject.Create;

  { Rota /api/v1/ordens-servico }
  vPathOS := TJSONObject.Create;
  vGetOS := TJSONObject.Create;
  vGetOS.Add('summary', 'Lista ordens de servico de forma paginada');
  vGetOS.Add('tags', TJSONArray.Create(['Ordens de Servico']));

  { Requisito de seguranca Bearer }
  vSecurityArr := TJSONArray.Create;
  vSecItem := TJSONObject.Create;
  vSecItem.Add('bearerAuth', TJSONArray.Create);
  vSecurityArr.Add(vSecItem);
  vGetOS.Add('security', vSecurityArr);

  { Resposta 200 OK }
  vResponses := TJSONObject.Create;
  vResp200 := TJSONObject.Create;
  vResp200.Add('description', 'Lista paginada recuperada com sucesso');

  vContJSON := TJSONObject.Create;
  vSchemaRef := TJSONObject.Create;
  vSchemaRef.Add('type', 'array');
  vSchemaRef.Add('items', TJSONObject.Create(
    ['$ref', '#/components/schemas/OrdemServico']));
  vContJSON.Add('schema', vSchemaRef);

  vResp200.Add('content', TJSONObject.Create(
    ['application/json', vContJSON]));
  vResponses.Add('200', vResp200);

  vGetOS.Add('responses', vResponses);
  vPathOS.Add('get', vGetOS);
  Result.Add('/api/v1/ordens-servico', vPathOS);
end;

class function TOpenAPIGenerator.GerarEspecificacao: TJSONObject;
var
  vComponents: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('openapi', '3.0.3');
  Result.Add('info', CriarInfo);

  vComponents := TJSONObject.Create;
  vComponents.Add('securitySchemes', CriarSecuritySchemes);
  vComponents.Add('schemas', CriarSchemas);
  Result.Add('components', vComponents);

  Result.Add('paths', CriarPaths);
end;

end.
```

### 3.2 Mapeamento de Parâmetros de Query String e Erros RFC 7807

Além de documentar respostas de sucesso `200 OK` e `201 Created`, uma 
especificação profissional deve instruir os desenvolvedores clientes 
sobre filtros disponíveis na URL e estruturas de erro padronizadas.

Para documentar os parâmetros de paginação e filtros vistos no Módulo 13, 
adicionamos um array `parameters` ao nó da operação:

```json
[
  {
    "name": "page",
    "in": "query",
    "required": false,
    "description": "Numero da pagina a ser recuperada (padrao: 1)",
    "schema": { "type": "integer", "default": 1 }
  },
  {
    "name": "limit",
    "in": "query",
    "required": false,
    "description": "Quantidade de registros por pagina (maximo: 100)",
    "schema": { "type": "integer", "default": 10 }
  },
  {
    "name": "status",
    "in": "query",
    "required": false,
    "description": "Filtro por status da OS",
    "schema": {
      "type": "string",
      "enum": ["ABERTA", "EM_EXECUCAO", "CONCLUIDA", "CANCELADA"]
    }
  }
]
```

Para as respostas de erro HTTP `400 Bad Request`, `401 Unauthorized` e 
`422 Unprocessable Entity`, vinculamos o schema `ProblemDetails` via 
referência `$ref`:

```json
"422": {
  "description": "Regra de negocio violada",
  "content": {
    "application/problem+json": {
      "schema": {
        "$ref": "#/components/schemas/ProblemDetails"
      }
    }
  }
}
```

Dessa forma, o consumidor da API sabe exatamente que, ao receber um erro 
`422`, o corpo conterá os campos padronizados `type`, `title`, `status`, 
`detail` e `instance`.

### 3.2 Página HTML do Swagger UI Embarcado

Criamos a unit `Core.SwaggerUI.pas`, que gera o HTML autocontido 
configurado para consumir o endpoint de especificação:

```pascal
unit Core.SwaggerUI;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes;

type
  TSwaggerUIBuilder = class
  public
    class function ObterHTML(const ASpecURL: string): string; static;
  end;

implementation

class function TSwaggerUIBuilder.ObterHTML(
  const ASpecURL: string): string;
begin
  Result := 
    '<!DOCTYPE html>' + LineEnding +
    '<html lang="pt-BR">' + LineEnding +
    '<head>' + LineEnding +
    '  <meta charset="UTF-8">' + LineEnding +
    '  <title>ConnectOS API — Swagger</title>' + LineEnding +
    '  <link rel="stylesheet" ' + 
    'href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css">' + 
    LineEnding +
    '  <style>' + LineEnding +
    '    html { box-sizing: border-box; overflow-y: scroll; }' + 
    LineEnding +
    '    *, *:before, *:after { box-sizing: inherit; }' + LineEnding +
    '    body { margin:0; background: #fafafa; }' + LineEnding +
    '  </style>' + LineEnding +
    '</head>' + LineEnding +
    '<body>' + LineEnding +
    '  <div id="swagger-ui"></div>' + LineEnding +
    '  <script ' +
    'src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js">' + 
    '</script>' + LineEnding +
    '  <script>' + LineEnding +
    '    window.onload = function() {' + LineEnding +
    '      window.ui = SwaggerUIBundle({' + LineEnding +
    '        url: "' + ASpecURL + '",' + LineEnding +
    '        dom_id: "#swagger-ui",' + LineEnding +
    '        deepLinking: true,' + LineEnding +
    '        presets: [' + LineEnding +
    '          SwaggerUIBundle.presets.apis,' + LineEnding +
    '          SwaggerUIBundle.SwaggerUIStandalonePreset' + LineEnding +
    '        ],' + LineEnding +
    '        layout: "BaseLayout"' + LineEnding +
    '      });' + LineEnding +
    '    };' + LineEnding +
    '  </script>' + LineEnding +
    '</body>' + LineEnding +
    '</html>';
end;

end.
```

### 3.3 Controller Horse para Swagger e OpenAPI

Integramos as rotas de documentação no Horse (`Controllers.Swagger.pas`):

```pascal
unit Controllers.Swagger;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, fpjson, Horse, Core.OpenAPI, Core.SwaggerUI;

type
  TSwaggerController = class
  public
    class procedure RegistrarRotas;
    class procedure ObterHTML(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
    class procedure ObterEspecificacaoJSON(Req: THorseRequest; 
      Res: THorseResponse; Next: TNextProc);
  end;

implementation

class procedure TSwaggerController.RegistrarRotas;
begin
  THorse.Get('/api/docs', @ObterHTML);
  THorse.Get('/api/docs/openapi.json', @ObterEspecificacaoJSON);
end;

class procedure TSwaggerController.ObterHTML(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vHTML: string;
begin
  vHTML := TSwaggerUIBuilder.ObterHTML('/api/docs/openapi.json');
  Res.RawWebResponse.ContentType := 'text/html; charset=utf-8';
  Res.Send(vHTML);
end;

class procedure TSwaggerController.ObterEspecificacaoJSON(
  Req: THorseRequest; Res: THorseResponse; Next: TNextProc);
var
  vJSON: TJSONObject;
begin
  vJSON := TOpenAPIGenerator.GerarEspecificacao;
  try
    Res.Status(200).Send<TJSONObject>(vJSON);
  except
    vJSON.Free;
    raise;
  end;
end;

end.
```

---

## 4. Testando o Endpoint

Abaixo estão os procedimentos práticos para testar a documentação gerada.

### 4.1 Acessando o Swagger UI pelo Navegador

Abra o navegador no endereço:
```text
http://localhost:9000/api/docs
```
A interface do Swagger UI será renderizada com o logotipo, título, schemas 
detalhados e botão **Authorize** para inserção do token Bearer JWT.

### 4.2 Baixando a Especificação OpenAPI via `curl`

```bash
curl -i -X GET http://localhost:9000/api/docs/openapi.json
```

**Resposta esperada (`200 OK` com especificação completa):**
```json
{
  "openapi": "3.0.3",
  "info": {
    "title": "ConnectOS API — Gestao de OS e Faturamento",
    "description": "API REST desenvolvida em Free Pascal e Lazarus",
    "version": "1.0.0"
  },
  "components": {
    "securitySchemes": {
      "bearerAuth": {
        "type": "http",
        "scheme": "bearer",
        "bearerFormat": "JWT"
      }
    },
    "schemas": {
      "Cliente": { "type": "object" },
      "OrdemServico": { "type": "object" },
      "ProblemDetails": { "type": "object" }
    }
  },
  "paths": {
    "/api/v1/ordens-servico": {
      "get": {
        "summary": "Lista ordens de servico de forma paginada"
      }
    }
  }
}
```

### 4.3 Integração com OpenAPI Generator para Clientes TypeScript e Mobile

Uma das maiores vantagens práticas de disponibilizar a especificação OpenAPI 
3.0 padronizada é permitir que equipes de frontend (React, Angular, Vue) e 
mobile (Flutter, Kotlin) gerem seus clientes HTTP tipados automaticamente, 
sem digitar uma única linha manual de código de consumo:

```bash
# Gerando cliente tipado em TypeScript com Axios
npx @openapitools/openapi-generator-cli generate \
  -i http://localhost:9000/api/docs/openapi.json \
  -g typescript-axios \
  -o ./frontend/src/api/client
```

Esse comando cria interfaces TypeScript idênticas aos nossos DTOs Pascal 
(`OrdemServico`, `Cliente`, `ProblemDetails`) e funções prontas para invocar 
os endpoints com tipagem estrita de parâmetros e respostas. Quando um campo 
da API é alterado no Lazarus, basta reexecutar o gerador no frontend para 
detectar inconsistências em tempo de compilação.

---

## 5. Armadilhas Comuns e Troubleshooting no FPC/Lazarus

### 5.1 Content-Type Incorreto ao Servir HTML
Ao devolver páginas web pelo Horse, se você usar `Res.Send(vHTML)` sem 
definir explicitamente `Res.RawWebResponse.ContentType := 'text/html; charset=utf-8'`, 
o navegador pode interpretar o arquivo como `text/plain` e exibir o código 
fonte HTML em vez de renderizá-lo.

### 5.2 Dupla Destruição de `TJSONObject` no Horse
No método `ObterEspecificacaoJSON`, o Horse assume a propriedade do objeto 
ao enviar via `Res.Send<TJSONObject>(vJSON)`. Nunca chame `vJSON.Free` após 
a linha do `Send`, sob risco de causar corrupção de heap no FPC. O bloco 
`except` deve conter `vJSON.Free` apenas para liberar a memória caso ocorra 
uma exceção antes do envio bem-sucedido.

### 5.3 Caracteres Não-ASCII no JSON
Ao montar descrições em português (com acentos como "Gestão", "Serviço"), 
certifique-se de salvar os arquivos fontes `.pas` com codificação **UTF-8 
sem BOM**. No Free Pascal, a diretiva `{$H+}` garante strings dinâmicas 
compatíveis com UTF-8 nativo no Lazarus.

### 5.4 Erros de CORS ao Utilizar o Swagger UI Externo
Se a sua equipe optar por hospedar o Swagger UI em um domínio separado 
(ex: `docs.connectos.com.br`) consumindo a API em `api.connectos.com.br`, o 
navegador bloqueará as chamadas *Try it out* se o middleware `horse-cors` 
não estiver configurado para autorizar a origem da documentação e os 
cabeçalhos customizados (`Authorization`, `Content-Type`). Garanta que o 
CORS libere o método `OPTIONS` e exponha os headers necessários conforme 
visto no Módulo 07.

### 5.5 Content Security Policy (CSP) e CDN Bloqueada
Em ambientes corporativos com políticas rígidas de segurança de conteúdo 
(CSP), o navegador pode bloquear o carregamento dos scripts e estilos da 
CDN do Swagger (`unpkg.com`). Caso sua API opere em redes isoladas sem 
acesso à internet pública (*air-gapped*), armazene os arquivos `swagger-ui.css` 
e `swagger-ui-bundle.js` localmente em um diretório do servidor e configure 
o Horse para servi-los estaticamente via `horse-octet-stream` ou rotas 
estáticas locais.

---

## 6. Resumo Executivo e Checklist de Revisão

Neste módulo, dotamos nossa API de um ecossistema completo de documentação 
viva e interativa no padrão OpenAPI 3.0, servida nativamente pelo Horse sem 
qualquer dependência de ferramentas externas.

### Checklist de Revisão
- [ ] A especificação obedece estritamente ao formato padronizado OpenAPI 3.0?
- [ ] O esquema de segurança Bearer JWT está configurado em `securitySchemes`?
- [ ] Os modelos de dados (`Cliente`, `OrdemServico`, `ProblemDetails`) 
      estão mapeados em `components/schemas`?
- [ ] A interface do Swagger UI é servida na rota `/api/docs` com header 
      `text/html; charset=utf-8`?
- [ ] O endpoint JSON `/api/docs/openapi.json` responde com status 200 OK 
      e validação de sintaxe JSON íntegra?
- [ ] Em produção restrita, a rota de documentação pode ser desativada 
      por configuração de ambiente?
