unit Core.ConnectionPool;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, syncobjs, IBConnection, sqldb,
  Core.Exceptions;

type
  { Representa uma conexao fisica rastreada no pool }
  TPooledConnection = class
  private
    FConnection: TIBConnection;
    FTransaction: TSQLTransaction;
    FEmUso: Boolean;
    FUltimoUso: TDateTime;
    FId: Integer;
  public
    constructor Create(const AHost, ABanco, AUser, APass: string;
      APorta: Integer = 3050);
    destructor Destroy; override;
    procedure ResetarEstado;
    property Connection: TIBConnection read FConnection;
    property Transaction: TSQLTransaction read FTransaction;
    property EmUso: Boolean read FEmUso write FEmUso;
    property UltimoUso: TDateTime read FUltimoUso write FUltimoUso;
    property Id: Integer read FId write FId;
  end;

  { Contrato para o RAII de devolucao automatica }
  IConnectionWrapper = interface
    ['{B9D19E2B-9876-4321-ABCD-1234567890AB}']
    function Connection: TIBConnection;
    function Transaction: TSQLTransaction;
    function PooledConnection: TPooledConnection;
  end;

  { Implementacao concreta do wrapper RAII }
  TConnectionWrapper = class(TInterfacedObject, IConnectionWrapper)
  private
    FPooled: TPooledConnection;
  public
    constructor Create(APooled: TPooledConnection);
    destructor Destroy; override;
    function Connection: TIBConnection;
    function Transaction: TSQLTransaction;
    function PooledConnection: TPooledConnection;
  end;

  { Gerenciador central do Pool de Conexoes }
  TFirebirdConnectionPool = class
  private
    class var FInstance: TFirebirdConnectionPool;
    FSection: TCriticalSection;
    FList: TList;
    FHost: string;
    FBanco: string;
    FUser: string;
    FPass: string;
    FPorta: Integer;
    FMinPoolSize: Integer;
    FMaxPoolSize: Integer;
    FTimeoutMS: Cardinal;
    function CriarConexaoFisica: TPooledConnection;
  public
    constructor Create;
    destructor Destroy; override;
    class function Instance: TFirebirdConnectionPool; static;
    class procedure Inicializar(const AHost, ABanco, AUser: string;
      const APass: string; APorta: Integer = 3050; AMin: Integer = 5;
      AMax: Integer = 20);
    class procedure Finalizar;
    function Acquire: IConnectionWrapper;
    procedure ReleaseConnection(APooled: TPooledConnection);
    function TotalConexoes: Integer;
    function ConexoesEmUso: Integer;
  end;

implementation

{ TPooledConnection }

constructor TPooledConnection.Create(const AHost, ABanco, AUser,
  APass: string; APorta: Integer);
begin
  inherited Create;
  FEmUso := False;
  FUltimoUso := Now;

  FConnection := TIBConnection.Create(nil);
  FConnection.HostName := AHost;
  FConnection.DatabaseName := ABanco;
  FConnection.UserName := AUser;
  FConnection.Password := APass;
  FConnection.Params.Add('Port=' + IntToStr(APorta));
  FConnection.Params.Add('lc_ctype=UTF8');
  FConnection.Params.Add('isc_tpb_read_committed');
  FConnection.Params.Add('isc_tpb_rec_version');
  FConnection.Params.Add('isc_tpb_nowait');
  FConnection.KeepConnection := True;

  FTransaction := TSQLTransaction.Create(nil);
  FTransaction.Database := FConnection;
  FTransaction.Action := caRollback;
  FTransaction.Params.Add('isc_tpb_read_committed');
  FTransaction.Params.Add('isc_tpb_rec_version');
  FTransaction.Params.Add('isc_tpb_nowait');

  FConnection.Transaction := FTransaction;
  FConnection.Open;
end;

destructor TPooledConnection.Destroy;
begin
  try
    if Assigned(FTransaction) and FTransaction.Active then
      FTransaction.Rollback;
  except
  end;
  try
    if Assigned(FConnection) and FConnection.Connected then
      FConnection.Close;
  except
  end;
  FTransaction.Free;
  FConnection.Free;
  inherited Destroy;
end;

procedure TPooledConnection.ResetarEstado;
begin
  if Assigned(FTransaction) and FTransaction.Active then
  begin
    try
      FTransaction.Rollback;
    except
      try
        FConnection.Close;
        FConnection.Open;
      except
      end;
    end;
  end;
  FEmUso := False;
  FUltimoUso := Now;
end;

{ TConnectionWrapper }

constructor TConnectionWrapper.Create(APooled: TPooledConnection);
begin
  inherited Create;
  FPooled := APooled;
end;

destructor TConnectionWrapper.Destroy;
begin
  if Assigned(FPooled) then
    TFirebirdConnectionPool.Instance.ReleaseConnection(FPooled);
  inherited Destroy;
end;

function TConnectionWrapper.Connection: TIBConnection;
begin
  Result := FPooled.Connection;
end;

function TConnectionWrapper.Transaction: TSQLTransaction;
begin
  Result := FPooled.Transaction;
end;

function TConnectionWrapper.PooledConnection: TPooledConnection;
begin
  Result := FPooled;
end;

{ TFirebirdConnectionPool }

constructor TFirebirdConnectionPool.Create;
begin
  inherited Create;
  FSection := TCriticalSection.Create;
  FList := TList.Create;
  FMinPoolSize := 5;
  FMaxPoolSize := 20;
  FTimeoutMS := 5000;
end;

destructor TFirebirdConnectionPool.Destroy;
var
  i: Integer;
begin
  FSection.Enter;
  try
    for i := 0 to FList.Count - 1 do
      TPooledConnection(FList[i]).Free;
    FList.Clear;
    FList.Free;
  finally
    FSection.Leave;
  end;
  FSection.Free;
  inherited Destroy;
end;

class function TFirebirdConnectionPool.Instance:
  TFirebirdConnectionPool;
begin
  if not Assigned(FInstance) then
    raise EAppException.Create('Pool de conexoes nao inicializado');
  Result := FInstance;
end;

class procedure TFirebirdConnectionPool.Inicializar(const AHost,
  ABanco, AUser: string; const APass: string; APorta: Integer;
  AMin, AMax: Integer);
var
  i: Integer;
begin
  if Assigned(FInstance) then Exit;
  FInstance := TFirebirdConnectionPool.Create;
  FInstance.FHost := AHost;
  FInstance.FBanco := ABanco;
  FInstance.FUser := AUser;
  FInstance.FPass := APass;
  FInstance.FPorta := APorta;
  FInstance.FMinPoolSize := AMin;
  FInstance.FMaxPoolSize := AMax;

  for i := 1 to AMin do
  begin
    try
      FInstance.FList.Add(FInstance.CriarConexaoFisica);
    except
      on E: Exception do
        WriteLn('[POOL INIT ERROR] Falha ao pre-aquecer: ' + E.Message);
    end;
  end;
end;

class procedure TFirebirdConnectionPool.Finalizar;
begin
  if Assigned(FInstance) then
  begin
    FInstance.Free;
    FInstance := nil;
  end;
end;

function TFirebirdConnectionPool.CriarConexaoFisica: TPooledConnection;
begin
  Result := TPooledConnection.Create(FHost, FBanco, FUser, FPass,
    FPorta);
end;

function TFirebirdConnectionPool.Acquire: IConnectionWrapper;
var
  vInicioMS: QWord;
  i: Integer;
  vItem: TPooledConnection;
begin
  vInicioMS := GetTickCount64;

  while True do
  begin
    FSection.Enter;
    try
      for i := 0 to FList.Count - 1 do
      begin
        vItem := TPooledConnection(FList[i]);
        if not vItem.EmUso then
        begin
          vItem.EmUso := True;
          vItem.UltimoUso := Now;
          Exit(TConnectionWrapper.Create(vItem));
        end;
      end;

      if FList.Count < FMaxPoolSize then
      begin
        vItem := CriarConexaoFisica;
        vItem.EmUso := True;
        vItem.UltimoUso := Now;
        FList.Add(vItem);
        Exit(TConnectionWrapper.Create(vItem));
      end;
    finally
      FSection.Leave;
    end;

    if (GetTickCount64 - vInicioMS) > FTimeoutMS then
      raise EAppException.Create('Timeout ao aguardar conexao do pool');

    Sleep(10);
  end;
end;

procedure TFirebirdConnectionPool.ReleaseConnection(
  APooled: TPooledConnection);
begin
  if not Assigned(APooled) then Exit;
  FSection.Enter;
  try
    APooled.ResetarEstado;
  finally
    FSection.Leave;
  end;
end;

function TFirebirdConnectionPool.TotalConexoes: Integer;
begin
  FSection.Enter;
  try
    Result := FList.Count;
  finally
    FSection.Leave;
  end;
end;

function TFirebirdConnectionPool.ConexoesEmUso: Integer;
var
  i: Integer;
begin
  Result := 0;
  FSection.Enter;
  try
    for i := 0 to FList.Count - 1 do
      if TPooledConnection(FList[i]).EmUso then
        Inc(Result);
  finally
    FSection.Leave;
  end;
end;

end.
