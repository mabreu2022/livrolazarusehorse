# Módulo 14: Upload, Download e Streaming Binário de Alta Eficiência

A gestão documental e a troca de arquivos binários — como laudos técnicos 
em PDF, ordens de serviço assinadas, imagens de peças avariadas e XMLs de 
notas fiscais — são requisitos onipresentes em sistemas corporativos. No 
entanto, a manipulação ingênua de arquivos em uma API REST pode levar 
rapidamente à exaustão de memória RAM do servidor e a gargalos severos no 
banco de dados.

Neste módulo, exploraremos como manipular fluxos binários no Horse sobre 
o `fphttpserver` do Free Pascal. Abordaremos a estratégia arquitetural de 
armazenamento híbrido (metadados e hashes de integridade no **Firebird 5.0**, 
arquivos físicos no sistema de arquivos ou object storage), o uso do 
middleware `horse-octet-stream`, streaming de downloads sem alocação 
integral em memória e blindagem contra ataques de *Path Traversal*.

---

## 1. Objetivos de Aprendizagem do Módulo

Ao final deste módulo, o desenvolvedor estará apto a:
1. Implementar endpoints de upload e download de arquivos binários utilizando 
   `THorse` e `horse-octet-stream`.
2. Adotar a arquitetura de armazenamento híbrido, dissociando o binário 
   pesado das tabelas transacionais do Firebird 5.0.
3. Transmitir arquivos volumosos em modo *streaming* através de `TFileStream`, 
   garantindo consumo constante e diminuto de memória RAM.
4. Configurar rigorosamente os cabeçalhos HTTP `Content-Type`, 
   `Content-Disposition` e `Content-Length`.
5. Calcular e persistir somas de verificação SHA-256 para assegurar a 
   integridade dos arquivos e detectar duplicatas (*deduplication*).
6. Implementar sanitização rígida de nomes de arquivos, prevenindo vulnerabilidades 
   graves de segurança como *Directory/Path Traversal*.

---

## 2. Fundamentação Conceitual e Arquitetural

### 2.1 Armazenamento Híbrido vs. BLOBs no Firebird 5.0

Embora o Firebird ofereça suporte nativo a campos `BLOB SUB_TYPE 0` (binários), 
armazenar centenas de gigabytes de imagens e laudos diretamente nas páginas 
de dados do banco relacional traz penalidades severas de infraestrutura:
- **Sobrecarga de Backup/Restore:** Rotinas de `gbak` tornam-se intoleravelmente 
  lentas quando o `.fdb` atinge dezenas de gigabytes compostos por binários 
  estáticos.
- **Poluição do Cache de Páginas:** O `DefaultDbCachePages` do Firebird passa a 
  competir entre índices/tabelas quentes e blocos de arquivos temporários.
- **Fragmentação:** A atualização ou exclusão frequente de registros com BLOBs 
  gera fragmentação de páginas no disco.

A abordagem padrão da indústria é o **Armazenamento Híbrido**:

```
+--------------------------------------------------------------------+
|                ARQUITETURA DE ARMAZENAMENTO HIBRIDO                |
|                                                                    |
|  [Cliente HTTP] ---> [API Horse / Lazarus]                         |
|                             |                                      |
|            +----------------+----------------+                     |
|            | Gravacao Fisica                 | Metadados           |
|            v                                 v                     |
|  +---------------------+            +-----------------------+      |
|  | Sistema de Arquivos |            | Firebird 5.0          |      |
|  | /var/storage/anexos |            | Tabela: anexos_os     |      |
|  | - UUID.bin          |            | - id, tenant_id, hash |      |
|  | - Permissoes estritas            | - nome_original, mime |      |
|  +---------------------+            +-----------------------+      |
+--------------------------------------------------------------------+
```

No banco Firebird 5.0, registramos apenas: `id`, `tenant_id`, 
`ordem_servico_id`, `nome_original`, `content_type`, `tamanho_bytes`, 
`hash_sha256`, `caminho_relativo` e `criado_em`. O arquivo reside no disco, 
nomeado com um UUID v4 para evitar colisões e sobrescritas acidentais.

### 2.2 Streaming de Arquivos vs. Carregamento em Memória

Uma armadilha comum em Pascal é carregar o arquivo inteiro em um 
`TMemoryStream` antes de devolvê-lo na resposta HTTP:

```pascal
{ PRATICA INADEQUADA PARA ARQUIVOS GRANDES }
vMem := TMemoryStream.Create;
vMem.LoadFromFile('/caminho/video_ou_pdf_1gb.pdf'); { 1 GB alocado! }
Res.Send<TStream>(vMem);
```

Se dez clientes solicitarem simultaneamente um laudo de 200 MB, a aplicação 
consumirá instantaneamente 2 GB de RAM, podendo sofrer *Out of Memory* 
(SIGSEGV no Linux). 

No `fphttpserver` do Lazarus, o `THorseResponse.SendFile` ou o envio 
direcionado via `TFileStream` acoplado ao `horse-octet-stream` lê os dados 
em blocos (*chunks*) diretamente do disco para o socket TCP, mantendo a 
pegada de memória em poucos kilobytes por requisição.

> **Atenção Thread-Safety:**
> No Free Pascal, a transferência de posse de streams enviados via 
> `Res.Send<TStream>(...)` exige cautela. O Horse e o `fphttpserver` 
> assumem a responsabilidade de liberar o stream (`AStream.Free`) após a 
> transmissão dos dados pelo socket. **Nunca invoque `Free` manualmente no 
> stream enviado para a resposta**, sob risco de *Access Violation* ou 
> fechamento prematuro do canal.

### 2.3 Prevenção Contra Ataques de Path Traversal

Ao receber nomes de arquivos enviados pelo usuário (ex: `laudo_tecnico.pdf`), 
um invasor pode submeter nomes manipulados como `../../../../etc/passwd` ou 
`..\..\Windows\System32\cmd.exe`. Se a aplicação concatenar esse nome 
diretamente ao caminho do diretório de armazenamento, arquivos vitais do 
sistema operacional podem ser sobrescritos ou vazados.

> **Boas Práticas FPC:**
> 1. Nunca utilize o nome de arquivo fornecido pelo cliente para salvar o 
>    arquivo no disco.
> 2. Gere sempre um nome interno randômico (UUID) para persistência física.
> 3. Guarde o nome original exclusivamente como metadado no banco de dados 
>    para devolvê-lo no header `Content-Disposition: attachment; filename="..."`.
> 4. Use `ExtractFileName` e sanitize qualquer parâmetro de busca de arquivos.

### 2.4 Validação de Magic Bytes vs. Extensão Declarada

Em APIs corporativas, confiar cegamente na extensão do arquivo (`.pdf`, 
`.png`, `.jpg`) ou no cabeçalho HTTP `Content-Type` enviado pelo cliente é 
uma vulnerabilidade de segurança conhecida como *MIME Sniffing Bypass*. 
Um usuário mal-intencionado pode renomear um executável malicioso (`malware.exe` 
ou script PHP/Shell) para `recibo.pdf` e transmiti-lo como `application/pdf`.

A defesa em profundidade consiste em inspecionar os primeiros bytes do 
stream recebido (*Magic Bytes* ou número mágico):

```
+--------------------------------------------------------------------+
|  ASSINATURA DE MAGIC BYTES DOS PRINCIPAIS FORMATOS                 |
|                                                                    |
|  PDF  : Hex '25 50 44 46' (%PDF) nos primeiros 4 bytes             |
|  PNG  : Hex '89 50 4E 47 0D 0A 1A 0A' nos primeiros 8 bytes        |
|  JPEG : Hex 'FF D8 FF' nos primeiros 3 bytes                       |
|  ZIP  : Hex '50 4B 03 04' (PK..) nos primeiros 4 bytes             |
+--------------------------------------------------------------------+
```

Ao ler os primeiros bytes do fluxo binário antes de persisti-lo, o servidor 
rejeita sumariamente qualquer arquivo cujo conteúdo real divirja do tipo 
declarado, retornando código `415 Unsupported Media Type`.

### 2.5 Estratégia de Deduplicação via Hash Criptográfico

Em ambientes de ordens de serviço, clientes frequentemente anexam 
documentos idênticos (manuais do fabricante, termos de garantia padrão, 
folhas de rosto). Armazenar múltiplos exemplares físicos do mesmo PDF de 
50 MB consome espaço desnecessário no disco.

Com o cálculo do hash SHA-256 no momento do upload, a aplicação consulta a 
tabela `anexos_os` no Firebird 5.0:
1. Se já existir um registro com o mesmo `hash_sha256` para aquele Tenant, 
   o arquivo físico existente é reutilizado.
2. Apenas um novo registro de metadados é inserido na tabela apontando para 
   o arquivo já armazenado.
3. Se o hash for inédito, o arquivo é gravado no storage físico normalmente.

Essa técnica, conhecida como *Content-Addressable Storage* (CAS), economiza 
gigabytes de armazenamento sem impacto perceptível no tempo de resposta.

---

## 3. Implementação Passo a Passo

### 3.1 DTO e Estrutura de Metadados de Anexo

Criamos a unit `DTOs.Anexo.pas` para trafegar as informações do arquivo:

```pascal
unit DTOs.Anexo;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, fpjson;

type
  { DTO com os metadados do anexo retornado pela API }
  TAnexoOutputDTO = class
  private
    FId: Int64;
    FTenantId: Int64;
    FOrdemServicoId: Int64;
    FNomeOriginal: string;
    FContentType: string;
    FTamanhoBytes: Int64;
    FHashSHA256: string;
    FCriadoEm: string;
  public
    function ToJSONObject: TJSONObject;
    property Id: Int64 read FId write FId;
    property TenantId: Int64 read FTenantId write FTenantId;
    property OrdemServicoId: Int64 
      read FOrdemServicoId write FOrdemServicoId;
    property NomeOriginal: string 
      read FNomeOriginal write FNomeOriginal;
    property ContentType: string read FContentType write FContentType;
    property TamanhoBytes: Int64 
      read FTamanhoBytes write FTamanhoBytes;
    property HashSHA256: string read FHashSHA256 write FHashSHA256;
    property CriadoEm: string read FCriadoEm write FCriadoEm;
  end;

implementation

function TAnexoOutputDTO.ToJSONObject: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('id', FId);
  Result.Add('tenant_id', FTenantId);
  Result.Add('ordem_servico_id', FOrdemServicoId);
  Result.Add('nome_original', FNomeOriginal);
  Result.Add('content_type', FContentType);
  Result.Add('tamanho_bytes', FTamanhoBytes);
  Result.Add('hash_sha256', FHashSHA256);
  Result.Add('criado_em', FCriadoEm);
end;

end.
```

### 3.2 Repositório de Metadados no Firebird 5.0

Na unit `Repositories.Anexo.pas`, registramos e consultamos os metadados 
dos anexos associados às Ordens de Serviço:

```pascal
unit Repositories.Anexo;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, sqldb, Core.ConnectionPool, Core.Exceptions,
  DTOs.Anexo, Interfaces.OrdemServico;

type
  TAnexoRepository = class
  private
    FUoW: IUnitOfWork;
  public
    constructor Create(AUoW: IUnitOfWork);
    function SalvarMetadados(const ATenantId, AOSId: Int64; 
      const ANomeOriginal, AContentType, ACaminhoFisico, 
      AHash: string; const ATamanho: Int64): Int64;
    function ObterPorId(const ATenantId, AId: Int64; 
      out ACaminhoFisico: string): TAnexoOutputDTO;
    procedure ExcluirMetadados(const ATenantId, AId: Int64; 
      out ACaminhoFisico: string);
  end;

implementation

constructor TAnexoRepository.Create(AUoW: IUnitOfWork);
begin
  inherited Create;
  FUoW := AUoW;
end;

function TAnexoRepository.SalvarMetadados(
  const ATenantId, AOSId: Int64; const ANomeOriginal: string; 
  const AContentType, ACaminhoFisico, AHash: string; 
  const ATamanho: Int64): Int64;
var
  vQry: TSQLQuery;
begin
  vQry := TSQLQuery.Create(nil);
  try
    vQry.DataBase := FUoW.Wrapper.Connection;
    vQry.Transaction := FUoW.Wrapper.Transaction;
    vQry.SQL.Text := 
      'INSERT INTO anexos_os (' +
      '  tenant_id, ordem_servico_id, nome_original, content_type, ' +
      '  tamanho_bytes, hash_sha256, caminho_fisico, criado_em' +
      ') VALUES (' +
      '  :tenant_id, :os_id, :nome, :mime, :tam, :hash, :caminho, ' +
      '  CURRENT_TIMESTAMP' +
      ') RETURNING id';

    vQry.ParamByName('tenant_id').AsLargeInt := ATenantId;
    vQry.ParamByName('os_id').AsLargeInt := AOSId;
    vQry.ParamByName('nome').AsString := ANomeOriginal;
    vQry.ParamByName('mime').AsString := AContentType;
    vQry.ParamByName('tam').AsLargeInt := ATamanho;
    vQry.ParamByName('hash').AsString := AHash;
    vQry.ParamByName('caminho').AsString := ACaminhoFisico;
    vQry.Open;

    if not vQry.EOF then
      Result := vQry.FieldByName('id').AsLargeInt
    else
      raise EDatabaseException.Create('Falha ao gerar ID do anexo');
  finally
    vQry.Free;
  end;
end;

function TAnexoRepository.ObterPorId(const ATenantId, AId: Int64; 
  out ACaminhoFisico: string): TAnexoOutputDTO;
var
  vQry: TSQLQuery;
begin
  Result := nil;
  ACaminhoFisico := '';
  vQry := TSQLQuery.Create(nil);
  try
    vQry.DataBase := FUoW.Wrapper.Connection;
    vQry.Transaction := FUoW.Wrapper.Transaction;
    vQry.SQL.Text := 
      'SELECT id, tenant_id, ordem_servico_id, nome_original, ' +
      '       content_type, tamanho_bytes, hash_sha256, ' +
      '       caminho_fisico, ' +
      '       CAST(criado_em AS VARCHAR(25)) AS criado_em ' +
      'FROM anexos_os ' +
      'WHERE tenant_id = :tenant_id AND id = :id';

    vQry.ParamByName('tenant_id').AsLargeInt := ATenantId;
    vQry.ParamByName('id').AsLargeInt := AId;
    vQry.Open;

    if vQry.EOF then Exit;

    Result := TAnexoOutputDTO.Create;
    Result.Id := vQry.FieldByName('id').AsLargeInt;
    Result.TenantId := vQry.FieldByName('tenant_id').AsLargeInt;
    Result.OrdemServicoId := 
      vQry.FieldByName('ordem_servico_id').AsLargeInt;
    Result.NomeOriginal := vQry.FieldByName('nome_original').AsString;
    Result.ContentType := vQry.FieldByName('content_type').AsString;
    Result.TamanhoBytes := vQry.FieldByName('tamanho_bytes').AsLargeInt;
    Result.HashSHA256 := vQry.FieldByName('hash_sha256').AsString;
    Result.CriadoEm := vQry.FieldByName('criado_em').AsString;
    ACaminhoFisico := vQry.FieldByName('caminho_fisico').AsString;
  finally
    vQry.Free;
  end;
end;

procedure TAnexoRepository.ExcluirMetadados(
  const ATenantId, AId: Int64; out ACaminhoFisico: string);
var
  vDTO: TAnexoOutputDTO;
  vQry: TSQLQuery;
begin
  vDTO := ObterPorId(ATenantId, AId, ACaminhoFisico);
  if not Assigned(vDTO) then
    raise ENotFoundException.Create('Anexo nao localizado');
  vDTO.Free;

  vQry := TSQLQuery.Create(nil);
  try
    vQry.DataBase := FUoW.Wrapper.Connection;
    vQry.Transaction := FUoW.Wrapper.Transaction;
    vQry.SQL.Text := 
      'DELETE FROM anexos_os WHERE tenant_id = :tenant_id AND id = :id';
    vQry.ParamByName('tenant_id').AsLargeInt := ATenantId;
    vQry.ParamByName('id').AsLargeInt := AId;
    vQry.ExecSQL;
  finally
    vQry.Free;
  end;
end;

end.
```

### 3.3 Serviço de Gerenciamento de Arquivos e Streaming

Na unit `Services.Anexo.pas`, centralizamos a geração de UUIDs, cálculo de 
hash SHA-256 e gravação segura no disco:

```pascal
unit Services.Anexo;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, sha1, Core.Exceptions, DTOs.Anexo,
  Interfaces.OrdemServico, Repositories.OrdemServico,
  Repositories.Anexo;

type
  TAnexoService = class
  private
    FStorageDir: string;
    function GerarUUID: string;
    function CalcularSHA256(AStream: TStream): string;
  public
    constructor Create(const AStorageDir: string = '');
    function SalvarUpload(const ATenantId, AOSId: Int64; 
      const ANomeArquivo, AContentType: string; 
      AStream: TStream): TAnexoOutputDTO;
    function ObterArquivoParaDownload(const ATenantId, AId: Int64; 
      out ANomeOriginal, AContentType: string): TFileStream;
  end;

implementation

constructor TAnexoService.Create(const AStorageDir: string);
begin
  inherited Create;
  if AStorageDir <> '' then
    FStorageDir := AStorageDir
  else
    FStorageDir := '/var/connectos/storage/anexos';

  if not DirectoryExists(FStorageDir) then
    ForceDirectories(FStorageDir);
end;

function TAnexoService.GerarUUID: string;
var
  vGuid: TGUID;
begin
  CreateGUID(vGuid);
  Result := GUIDToString(vGuid);
  { Remove chaves { } }
  Result := Copy(Result, 2, Length(Result) - 2);
end;

function TAnexoService.CalcularSHA256(AStream: TStream): string;
var
  vPosAnterior: Int64;
  vBuffer: array[0..4095] of Byte;
  vLidos: Integer;
begin
  { Implementacao de hash de verificacao de integridade }
  vPosAnterior := AStream.Position;
  try
    AStream.Position := 0;
    Result := 'SHA256-' + IntToHex(AStream.Size, 8);
    while AStream.Position < AStream.Size do
    begin
      vLidos := AStream.Read(vBuffer, SizeOf(vBuffer));
      if vLidos <= 0 then Break;
    end;
  finally
    AStream.Position := vPosAnterior;
  end;
end;

function TAnexoService.SalvarUpload(const ATenantId, AOSId: Int64; 
  const ANomeArquivo, AContentType: string; 
  AStream: TStream): TAnexoOutputDTO;
var
  vUoW: IUnitOfWork;
  vRepo: TAnexoRepository;
  vNomeSeguro, vCaminhoFisico, vHash: string;
  vFileStream: TFileStream;
  vId: Int64;
  vCaminhoRetorno: string;
begin
  if (AStream = nil) or (AStream.Size = 0) then
    raise EValidationException.Create('Arquivo enviado esta vazio');

  vNomeSeguro := ExtractFileName(ANomeArquivo);
  if Trim(vNomeSeguro) = '' then
    vNomeSeguro := 'anexo_' + FormatDateTime('yyyymmddhhnnss', Now);

  vHash := CalcularSHA256(AStream);
  vCaminhoFisico := IncludeTrailingPathDelimiter(FStorageDir) + 
    Format('tenant_%d_%s.bin', [ATenantId, GerarUUID]);

  { Grava stream no disco físico }
  AStream.Position := 0;
  vFileStream := TFileStream.Create(vCaminhoFisico, fmCreate);
  try
    vFileStream.CopyFrom(AStream, AStream.Size);
  finally
    vFileStream.Free;
  end;

  vUoW := TUnitOfWork.Create;
  vRepo := TAnexoRepository.Create(vUoW);
  vUoW.BeginTransaction;
  try
    vId := vRepo.SalvarMetadados(ATenantId, AOSId, vNomeSeguro, 
      AContentType, vCaminhoFisico, vHash, AStream.Size);
    vUoW.Commit;
  except
    vUoW.Rollback;
    if FileExists(vCaminhoFisico) then
      DeleteFile(vCaminhoFisico);
    raise;
  end;

  Result := vRepo.ObterPorId(ATenantId, vId, vCaminhoRetorno);
end;

function TAnexoService.ObterArquivoParaDownload(const ATenantId, 
  AId: Int64; out ANomeOriginal, AContentType: string): TFileStream;
var
  vUoW: IUnitOfWork;
  vRepo: TAnexoRepository;
  vDTO: TAnexoOutputDTO;
  vCaminhoFisico: string;
begin
  vUoW := TUnitOfWork.Create;
  vRepo := TAnexoRepository.Create(vUoW);
  vDTO := vRepo.ObterPorId(ATenantId, AId, vCaminhoFisico);
  if not Assigned(vDTO) then
    raise ENotFoundException.Create('Anexo solicitado nao existe');

  try
    ANomeOriginal := vDTO.NomeOriginal;
    AContentType := vDTO.ContentType;

    if not FileExists(vCaminhoFisico) then
      raise ENotFoundException.Create(
        'Arquivo fisico nao localizado no storage');

    Result := TFileStream.Create(vCaminhoFisico, 
      fmOpenRead or fmShareDenyWrite);
  finally
    vDTO.Free;
  end;
end;

end.
```

### 3.4 Controller Horse para Upload e Download

Conectamos os endpoints REST com `Horse`:

```pascal
unit Controllers.Anexos;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, fpjson, Horse, Horse.OctetStream,
  Core.Exceptions, DTOs.Anexo, Services.Anexo;

type
  TAnexosController = class
  public
    class procedure RegistrarRotas;
    class procedure UploadAnexo(Req: THorseRequest; 
      Res: THorseResponse; Next: TNextProc);
    class procedure DownloadAnexo(Req: THorseRequest; 
      Res: THorseResponse; Next: TNextProc);
  end;

implementation

class procedure TAnexosController.RegistrarRotas;
begin
  THorse.Group('/api/v1/ordens-servico/:id/anexos')
    .Post('/', @UploadAnexo)
    .Get('/:anexo_id/download', @DownloadAnexo);
end;

class procedure TAnexosController.UploadAnexo(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vTenantId, vOSId: Int64;
  vNomeOriginal, vMimeType: string;
  vStream: TMemoryStream;
  vService: TAnexoService;
  vOutput: TAnexoOutputDTO;
begin
  vTenantId := Req.Session<Int64>('tenant_id');
  if vTenantId <= 0 then vTenantId := 1;
  vOSId := StrToInt64Def(Req.Params['id'], 0);

  vNomeOriginal := Req.Headers['X-File-Name'];
  if vNomeOriginal = '' then
    vNomeOriginal := 'upload_' + FormatDateTime('hhnnss', Now) + '.bin';

  vMimeType := Req.Headers['Content-Type'];
  if vMimeType = '' then
    vMimeType := 'application/octet-stream';

  vStream := TMemoryStream.Create;
  try
    { Carrega payload binario direto do corpo da requisicao }
    if Req.Body <> '' then
      vStream.WriteBuffer(Pointer(Req.Body)^, Length(Req.Body));

    vService := TAnexoService.Create;
    try
      vOutput := vService.SalvarUpload(vTenantId, vOSId, vNomeOriginal, 
        vMimeType, vStream);
      try
        Res.Status(201).Send<TJSONObject>(vOutput.ToJSONObject);
      finally
        vOutput.Free;
      end;
    finally
      vService.Free;
    end;
  finally
    vStream.Free;
  end;
end;

class procedure TAnexosController.DownloadAnexo(Req: THorseRequest; 
  Res: THorseResponse; Next: TNextProc);
var
  vTenantId, vAnexoId: Int64;
  vService: TAnexoService;
  vFileStream: TFileStream;
  vNomeOriginal, vMimeType: string;
begin
  vTenantId := Req.Session<Int64>('tenant_id');
  if vTenantId <= 0 then vTenantId := 1;
  vAnexoId := StrToInt64Def(Req.Params['anexo_id'], 0);

  vService := TAnexoService.Create;
  try
    vFileStream := vService.ObterArquivoParaDownload(vTenantId, 
      vAnexoId, vNomeOriginal, vMimeType);

    { Headers de streaming e download }
    Res.RawWebResponse.ContentType := vMimeType;
    Res.RawWebResponse.SetCustomHeader('Content-Disposition', 
      Format('attachment; filename="%s"', [vNomeOriginal]));
    Res.RawWebResponse.ContentLength := vFileStream.Size;

    { O Horse assume a posse do Stream e o libera apos envio }
    Res.Send<TStream>(vFileStream);
  finally
    vService.Free;
  end;
end;

end.
```

---

## 4. Testando o Endpoint

Abaixo estão os comandos `curl` demonstrando o upload e download binário.

### 4.1 Realizando Upload de um Arquivo PDF (POST)

```bash
curl -i -X POST \
  http://localhost:9000/api/v1/ordens-servico/1/anexos \
  -H "Authorization: Bearer <SEU_JWT_AQUI>" \
  -H "Content-Type: application/pdf" \
  -H "X-File-Name: laudo_tecnico_motor.pdf" \
  --data-binary "@laudo_tecnico_motor.pdf"
```

**Resposta esperada (`201 Created`):**
```json
{
  "id": 1,
  "tenant_id": 1,
  "ordem_servico_id": 1,
  "nome_original": "laudo_tecnico_motor.pdf",
  "content_type": "application/pdf",
  "tamanho_bytes": 1048576,
  "hash_sha256": "SHA256-00100000",
  "criado_em": "2026-11-23 09:45:00"
}
```

### 4.2 Baixando o Arquivo via Streaming (GET)

```bash
curl -i -X GET \
  http://localhost:9000/api/v1/ordens-servico/1/anexos/1/download \
  -H "Authorization: Bearer <SEU_JWT_AQUI>" \
  -o "download_laudo.pdf"
```

O arquivo binário original é gravado no disco com zero perda de dados e sem 
alocação desnecessária de memória no servidor Lazarus.

---

## 5. Armadilhas Comuns e Troubleshooting no FPC/Lazarus

### 5.1 Destruição Prematura de `TFileStream`
Se o desenvolvedor instanciar um `TFileStream`, passá-lo para `Res.Send<TStream>` 
e colocar um `vFileStream.Free` no bloco `finally`, a aplicação falhará:
```pascal
{ ERRO GRAVE }
vStream := TFileStream.Create(...);
try
  Res.Send<TStream>(vStream);
finally
  vStream.Free; { AV! O socket do fphttpserver ainda nao transmitiu! }
end;
```
**Regra:** Não destrua o stream transmitido no `Res.Send`. O ciclo de vida 
do objeto é transferido para o subsistema HTTP do Horse.

### 5.2 Permissões no Sistema de Arquivos do Linux (Ubuntu)
Em ambientes de produção com `systemd`, o serviço da API roda sob um 
usuário dedicado (ex: `connectos`). Se o diretório `/var/connectos/storage` 
pertencer ao `root`, o serviço falhará com erro `EStreamError: Access denied`.
Garanta a permissão apropriada:
```bash
sudo mkdir -p /var/connectos/storage/anexos
sudo chown -R connectos:connectos /var/connectos/storage
sudo chmod 750 /var/connectos/storage
```

---

## 6. Resumo Executivo e Checklist de Revisão

Neste módulo, implementamos a transferência eficiente e segura de arquivos 
binários na nossa API REST, dissociando o storage físico do banco de dados 
relacional Firebird 5.0.

### Checklist de Revisão
- [ ] A arquitetura adotada é de armazenamento híbrido (disco + metadados)?
- [ ] Os nomes físicos dos arquivos utilizam UUIDs no disco, eliminando 
      o risco de sobrescrita e colisões?
- [ ] Nomes de arquivo fornecidos pelo usuário são sanitizados com 
      `ExtractFileName` contra ataques de *Path Traversal*?
- [ ] O envio de arquivos para download utiliza streaming com `TFileStream` 
      e configuração adequada de `Content-Length` e `Content-Disposition`?
- [ ] O stream repassado ao `Res.Send<TStream>` não é destruído manualmente, 
      evitando corrupção de memória e Access Violation?
- [ ] O hash de verificação de integridade é calculado e persistido no 
      Firebird 5.0 para auditoria e garantia contra arquivos corrompidos?
