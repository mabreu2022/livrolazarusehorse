unit Controllers.Ping;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Classes,
  Horse;

type
  TControllersPing = class
  private
    class procedure DoGetPing(Req: THorseRequest; Res: THorseResponse; 
      Next: TNextProc);
    class procedure DoGetMetrics(Req: THorseRequest; 
      Res: THorseResponse; Next: TNextProc);
  public
    class procedure Registry;
  end;

implementation

{ TControllersPing }

class procedure TControllersPing.DoGetPing(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vPayload: string;
begin
  vPayload := '{"status":"pong",' +
              '"servico":"ConnectOSApi",' +
              '"timestamp":"' + 
              FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', Now) + 
              '"}';

  Res.Send(vPayload)
     .Status(THTTPStatus.OK);
end;

class procedure TControllersPing.DoGetMetrics(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vHeapStatus: TFPCHeapStatus;
  vPayload: string;
begin
  vHeapStatus := GetFPCHeapStatus;

  vPayload := '{"servico":"ConnectOSApi",' +
              '"fpc_version":"' + {$I %FPCVERSION%} + '",' +
              '"target_cpu":"' + {$I %FPCTARGETCPU%} + '",' +
              '"target_os":"' + {$I %FPCTARGETOS%} + '",' +
              '"heap_usado_bytes":' + 
              IntToStr(vHeapStatus.CurrHeapUsed) + ',' +
              '"heap_alocado_bytes":' + 
              IntToStr(vHeapStatus.CurrHeapSize) + ',' +
              '"heap_maximo_bytes":' + 
              IntToStr(vHeapStatus.MaxHeapUsed) + '}';

  Res.Send(vPayload)
     .Status(THTTPStatus.OK);
end;

class procedure TControllersPing.Registry;
begin
  THorse.Get('/ping', @DoGetPing);
  THorse.Get('/api/v1/metrics', @DoGetMetrics);
end;

end.
