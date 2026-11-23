unit Core.Exceptions;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  EAppException = class(Exception)
  private
    FStatusCode: Integer;
    FErrorCode: string;
  public
    constructor Create(const AMsg: string; AStatus: Integer = 400; 
      const AErrCode: string = 'ERRO_APLICACAO');
    property StatusCode: Integer read FStatusCode;
    property ErrorCode: string read FErrorCode;
  end;

  EBusinessException = class(EAppException)
  public
    constructor Create(const AMsg: string; 
      const AErrCode: string = 'REGRA_NEGOCIO_VIOLADA');
  end;

  ENotFoundException = class(EAppException)
  public
    constructor Create(const AMsg: string; 
      const AErrCode: string = 'RECURSO_NAO_ENCONTRADO');
  end;

  EConflictException = class(EAppException)
  public
    constructor Create(const AMsg: string; 
      const AErrCode: string = 'CONFLITO_ESTADO');
  end;

  EUnauthorizedException = class(EAppException)
  public
    constructor Create(const AMsg: string = 'Credenciais invalidas'; 
      const AErrCode: string = 'NAO_AUTORIZADO');
  end;

  EForbiddenException = class(EAppException)
  public
    constructor Create(const AMsg: string = 'Acesso negado ao recurso'; 
      const AErrCode: string = 'ACESSO_PROIBIDO');
  end;

implementation

{ EAppException }

constructor EAppException.Create(const AMsg: string; AStatus: Integer; 
  const AErrCode: string);
begin
  inherited Create(AMsg);
  FStatusCode := AStatus;
  FErrorCode := AErrCode;
end;

{ EBusinessException }

constructor EBusinessException.Create(const AMsg: string; 
  const AErrCode: string);
begin
  inherited Create(AMsg, 422, AErrCode);
end;

{ ENotFoundException }

constructor ENotFoundException.Create(const AMsg: string; 
  const AErrCode: string);
begin
  inherited Create(AMsg, 404, AErrCode);
end;

{ EConflictException }

constructor EConflictException.Create(const AMsg: string; 
  const AErrCode: string);
begin
  inherited Create(AMsg, 409, AErrCode);
end;

{ EUnauthorizedException }

constructor EUnauthorizedException.Create(const AMsg: string; 
  const AErrCode: string);
begin
  inherited Create(AMsg, 401, AErrCode);
end;

{ EForbiddenException }

constructor EForbiddenException.Create(const AMsg: string; 
  const AErrCode: string);
begin
  inherited Create(AMsg, 403, AErrCode);
end;

end.
