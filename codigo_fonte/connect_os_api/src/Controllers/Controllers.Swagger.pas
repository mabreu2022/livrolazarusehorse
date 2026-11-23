unit Controllers.Swagger;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, fpjson, Horse;

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
  vHTML := 
    '<!DOCTYPE html>' + LineEnding +
    '<html lang="pt-BR">' + LineEnding +
    '<head>' + LineEnding +
    '  <meta charset="UTF-8">' + LineEnding +
    '  <title>ConnectOS API — Swagger</title>' + LineEnding +
    '  <link rel="stylesheet" ' + 
    'href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css">' + 
    LineEnding +
    '</head>' + LineEnding +
    '<body>' + LineEnding +
    '  <div id="swagger-ui"></div>' + LineEnding +
    '  <script ' +
    'src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js">' + 
    '</script>' + LineEnding +
    '  <script>' + LineEnding +
    '    window.onload = function() {' + LineEnding +
    '      window.ui = SwaggerUIBundle({' + LineEnding +
    '        url: "/api/docs/openapi.json",' + LineEnding +
    '        dom_id: "#swagger-ui"' + LineEnding +
    '      });' + LineEnding +
    '    };' + LineEnding +
    '  </script>' + LineEnding +
    '</body>' + LineEnding +
    '</html>';

  Res.RawWebResponse.ContentType := 'text/html; charset=utf-8';
  Res.Send(vHTML);
end;

class procedure TSwaggerController.ObterEspecificacaoJSON(
  Req: THorseRequest; Res: THorseResponse; Next: TNextProc);
var
  vJSON, vInfo, vPaths: TJSONObject;
begin
  vJSON := TJSONObject.Create;
  try
    vJSON.Add('openapi', '3.0.3');

    vInfo := TJSONObject.Create;
    vInfo.Add('title', 'ConnectOS API');
    vInfo.Add('version', '1.0.0');
    vJSON.Add('info', vInfo);

    vPaths := TJSONObject.Create;
    vJSON.Add('paths', vPaths);

    Res.Status(200).Send<TJSONObject>(vJSON);
  except
    vJSON.Free;
    raise;
  end;
end;

end.
