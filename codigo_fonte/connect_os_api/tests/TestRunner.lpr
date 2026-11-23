program TestRunner;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Classes, consoletestrunner, fpcunit, testregistry,
  Test.Services.OrdemServico;

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
