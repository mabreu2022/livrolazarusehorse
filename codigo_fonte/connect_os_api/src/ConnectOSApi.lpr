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
  Middlewares.GlobalExceptionHandler,
  Middlewares.CORS,
  Middlewares.CorrelationId,
  Middlewares.Logger,
  Middlewares.RateLimit,
  Middlewares.AuthJWT,
  Controllers.Ping,
  Controllers.Auth,
  Controllers.Clientes;

const
  CHAVE_SECRETA_JWT = 'ChaveSecretaSuperProtegidaConnectOSApi2026';

procedure DoOnListen;
begin
  WriteLn('----------------------------------------------------');
  WriteLn('  CONNECT OS API - AUTENTICACAO JWT ATIVA           ');
  WriteLn('  - Auth JWT       : Ativo (Algoritmo HS256)        ');
  WriteLn('  - Portas         : http://0.0.0.0:' + IntToStr(THorse.Port));
  WriteLn('----------------------------------------------------');
  WriteLn('Pressione [CTRL+C] no console para encerrar.');
end;

var
  vPorta: Word;
begin
  vPorta := StrToIntDef(GetEnvironmentVariable('PORT'), 9000);
  THorse.Port := vPorta;

  TMiddlewareCORS.Configurar('*');
  TMiddlewareAuthJWT.Configurar(CHAVE_SECRETA_JWT);
  TControllersAuth.Configurar(CHAVE_SECRETA_JWT);

  { 1. SENTINELA GLOBAL DE EXCECOES }
  THorse.Use(@TMiddlewareGlobalExceptionHandler.Middleware);

  { 2. CORS E PREFLIGHT }
  THorse.Use(@TMiddlewareCORS.Middleware);

  { 3. PARSING JSON E TELEMETRIA }
  THorse.Use(Jhonson);
  THorse.Use(@TMiddlewareCorrelationId.Middleware);
  THorse.Use(@TMiddlewareLogger.Middleware);
  THorse.Use(@TMiddlewareRateLimit.Middleware);

  { 4. GUARDA DE AUTORIZACAO JWT }
  THorse.Use(@TMiddlewareAuthJWT.Middleware);

  { 5. REGISTRO DE ROTAS }
  TControllersPing.Registry;
  TControllersAuth.Registry;
  TControllersClientes.Registry;

  THorse.Listen(@DoOnListen);
end.
