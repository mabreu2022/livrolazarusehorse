unit Middlewares.GlobalExceptionHandler;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  Horse,
  Core.Exceptions,
  Core.ProblemDetails;

type
  TMiddlewareGlobalExceptionHandler = class
  public
    class procedure Middleware(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
  end;

implementation

{ TMiddlewareGlobalExceptionHandler }

class procedure TMiddlewareGlobalExceptionHandler.Middleware(
  Req: THorseRequest; Res: THorseResponse; Next: TNextProc);
var
  vCorrelationId: string;
begin
  try
    Next();
  except
    on E: EAppException do
    begin
      vCorrelationId := 
        Res.RawWebResponse.GetCustomHeader('X-Correlation-ID');

      TProblemDetails.CreateNew
        .SetType('https://api.connectos.com/erros/' + 
          LowerCase(E.ErrorCode))
        .SetTitle(E.ClassName)
        .SetStatus(E.StatusCode)
        .SetDetail(E.Message)
        .SetInstance(Req.RawWebRequest.PathInfo)
        .SendTo(Res);
    end;

    on E: Exception do
    begin
      vCorrelationId := 
        Res.RawWebResponse.GetCustomHeader('X-Correlation-ID');

      WriteLn(Format('[CRITICAL-ERROR] %s | CorrID: %s | Falha: %s: %s',
        [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now),
         vCorrelationId,
         E.ClassName,
         E.Message]));

      TProblemDetails.CreateNew
        .SetType('https://api.connectos.com/erros/erro-interno')
        .SetTitle('Erro Interno de Servidor')
        .SetStatus(500)
        .SetDetail('Ocorreu uma falha inesperada no processamento. ' +
                   'Informe o identificador de correlacao ao suporte.')
        .SetInstance(Req.RawWebRequest.PathInfo)
        .SendTo(Res);
    end;
  end;
end;

end.
