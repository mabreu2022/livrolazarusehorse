{======================================================================}
{ Projeto: Servidor HTTP Standalone de Alta Performance com Horse      }
{ Livro  : Desenvolvimento de APIs REST com Horse e Lazarus            }
{ Autor  : Mauricio Abreu                                              }
{ Modulo : 01 - Anatomia de um Servidor HTTP com Horse no Free Pascal  }
{======================================================================}
program PrimeiroServidor;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  SysUtils,
  Classes,
  Horse,
  Horse.Provider.FPHTTP;

procedure DoHealthCheck(Req: THorseRequest; Res: THorseResponse; 
  Next: TNextProc);
var
  vPayload: string;
begin
  vPayload := '{"status":"online",' +
              '"servico":"ConnectOSApi",' +
              '"engine":"Horse/FPC 3.2.2",' +
              '"timestamp":"' + 
              FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', Now) + 
              '"}';

  Res.Send(vPayload)
     .Status(THTTPStatus.OK);
end;

procedure DoEcho(Req: THorseRequest; Res: THorseResponse; 
  Next: TNextProc);
var
  vMensagem: string;
  vResposta: string;
begin
  vMensagem := Req.Query.Field('msg').AsString;
  if Trim(vMensagem) = '' then
    vMensagem := 'Nenhuma mensagem informada no parametro msg';

  vResposta := '{"eco":"' + vMensagem + '"}';

  Res.Send(vResposta)
     .Status(THTTPStatus.OK);
end;

procedure DoOnListen;
begin
  WriteLn('====================================================');
  WriteLn('  CONNECT OS API - SERVIDOR HTTP STANDALONE         ');
  WriteLn('  Ambiente  : Free Pascal ' + {$I %FPCVERSION%} + ' (' + 
          {$I %FPCTARGETCPU%} + '-' + {$I %FPCTARGETOS%} + ')');
  WriteLn('  Porta TCP : ' + IntToStr(THorse.Port));
  WriteLn('  Status    : Aguardando conexoes ativas...         ');
  WriteLn('====================================================');
  WriteLn('Pressione [CTRL+C] no terminal para interromper.');
  WriteLn('');
end;

var
  vPorta: Word;
  vPortaStr: string;
begin
  vPorta := 9000;
  if ParamCount >= 1 then
  begin
    vPortaStr := ParamStr(1);
    vPorta := StrToIntDef(vPortaStr, 9000);
  end;

  THorse.Port := vPorta;

  THorse.Get('/health', @DoHealthCheck);
  THorse.Get('/api/echo', @DoEcho);

  THorse.Listen(@DoOnListen);
end.
