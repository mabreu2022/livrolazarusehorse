# Módulo 19: Daemons de Produção com systemd e Windows Services

Em ambientes de produção corporativos, uma API REST não pode depender 
de sessões interativas de terminal abertas via SSH ou de janelas de console 
no desktop do administrador. Se o servidor for reiniciado para aplicação de 
patches de segurança do kernel ou se o processo sofrer um encerramento 
inesperado, o sistema operacional deve ser capaz de reiniciar a aplicação 
de forma autônoma em milissegundos.

Além disso, a API deve operar sob o princípio do menor privilégio (*Least 
Privilege*), executando sob um usuário dedicado do sistema, gerenciando 
limites de descritores de arquivos para suportar milhares de conexões TCP 
simultâneas e respondendo adequadamente a sinais de encerramento gracioso 
(*Graceful Shutdown*).

Neste módulo, aprenderemos a empacotar e gerenciar nossa API Horse como um 
daemon nativo do **systemd** no Ubuntu Linux 24.04 LTS e como um serviço do 
**Windows Service**, garantindo disponibilidade contínua, telemetria de 
logs com `journalctl` e ciclo de vida robusto.

---

## 1. Objetivos de Aprendizagem do Módulo

Ao término deste módulo, você será capaz de:
1. Projetar e configurar uma unidade de serviço nativa do **systemd** 
   (`/etc/systemd/system/connectos-api.service`) para o Linux.
2. Implementar a política de reinicialização automática (`Restart=always`) 
   e limites de segurança de sistema operacional (`LimitNOFILE=65536`).
3. Tratar sinais POSIX (`SIGTERM`, `SIGINT`) no Free Pascal para encerramento 
   gracioso, esvaziando o Pool de Conexões sem derrubar requisições ativas.
4. Operar o serviço com comandos de controle `systemctl` (start, stop, 
   restart, status, enable).
5. Analisar, filtrar e auditar logs do sistema através do utilitário 
   `journalctl` com rotação estruturada.
6. Configurar a execução da API como um **Windows Service** nativo 
   utilizando o gerenciador de serviços do Windows (`sc.exe` ou WinSW).

---

## 2. Fundamentação Conceitual e Arquitetural

### 2.1 A Arquitetura do systemd no Linux Moderno

O `systemd` é o sistema de inicialização (*init system*) e gerenciador de 
serviços padrão das principais distribuições Linux corporativas (Ubuntu, 
Debian, Red Hat, CentOS). Ele substituiu os antigos scripts SysVinit, 
oferecendo paralelização no boot, monitoramento de processos via cgroups 
(grupos de controle) e supervisão contínua:

```
+--------------------------------------------------------------------+
|                SUPERVISAO DE PROCESSOS VIA SYSTEMD                 |
|                                                                    |
|  [Kernel Linux]                                                    |
|         |                                                          |
|         v                                                          |
|  [systemd (PID 1)]                                                 |
|         |                                                          |
|         +---> Controla cgroup: system.slice/connectos-api.service  |
|         |        |                                                 |
|         |        v                                                 |
|         |     [connect_os_api (PID 1042)] <--- Roda como connectos |
|         |        |                                                 |
|         |        +---> stdout / stderr ---> [systemd-journald]     |
|         |                                                          |
|         +---> Se o processo cair: dispara RestartSec (5s) e revive |
|         +---> Se receber systemctl stop: envia SIGTERM gracioso    |
+--------------------------------------------------------------------+
```

### 2.2 O Desafio Crítico dos Descritores de Arquivos (`LimitNOFILE`)

No Linux, a máxima "tudo é um arquivo" aplica-se rigorosamente às conexões 
de rede. Cada socket TCP aberto por um cliente HTTP consumindo a API Horse 
utiliza um **descritor de arquivo** (*file descriptor*). 

Por padrão, a maioria das distribuições Linux impõe um limite moderado de 
1.024 descritores por processo para usuários comuns. Se a sua API receber 
1.500 requisições simultâneas em um pico de tráfego, o kernel rejeitará as 
novas conexões com o erro fatal:
```text
Socket Error: Too many open files (EMFILE)
```

> **Atenção Thread-Safety:**
> No arquivo de unidade do systemd, é obrigatório definir explicitamente 
> `LimitNOFILE=65536`. Essa diretiva eleva o teto de sockets simultâneos que 
> o Horse pode manter abertos, impedindo a negação de serviço por esgotamento 
> de descritores locais.

### 2.3 Encerramento Gracioso (*Graceful Shutdown*)

Quando o administrador emite `systemctl restart connectos-api` para aplicar 
uma nova versão, o systemd envia o sinal `SIGTERM` ao processo. Se a 
aplicação for abortada instantaneamente:
1. Requisições de clientes gravando faturamento ou ordens de serviço são 
   interrompidas pela metade.
2. Transações abertas no Firebird 5.0 sofrem rollback abrupto.
3. Conexões físicas do pool são fechadas forçadamente na `fbclient`.

O encerramento gracioso intercepta o sinal `SIGTERM`:
- Interrompe a aceitação de novas conexões HTTP no Horse (`THorse.StopListen`).
- Aguarda até 10 segundos para que as requisições em trânsito terminem.
- Esvazia e desconecta ordenadamente o `TFirebirdConnectionPool`.
- Finaliza o processo com código de saída 0.

### 2.4 A Arquitetura do Service Control Manager (SCM) no Windows

No ecossistema Microsoft Windows (Windows Server 2022 / Windows 11), os 
processos em segundo plano são orquestrados pelo subsistema central 
denominado **Service Control Manager (SCM)**. 

Diferente do Linux (onde qualquer binário executável console pode ser 
supervisionado diretamente pelo systemd), o Windows exige que o executável 
implemente um protocolo formal de comunicação RPC com o SCM:
1. Ao iniciar, a aplicação deve chamar a API Win32 `StartServiceCtrlDispatcher`.
2. O processo registra uma função de retorno (*Handler*) para responder a 
   comandos do sistema operacional (`SERVICE_CONTROL_STOP`, `SERVICE_CONTROL_PAUSE`).
3. Periodicamente, o serviço reporta seu estado operacional ao SCM 
   (`SERVICE_RUNNING`, `SERVICE_START_PENDING`, `SERVICE_STOPPED`).

O Lazarus disponibiliza o pacote nativo `lazdaemon`, que encapsula 
toda essa complexidade de baixo nível em classes estruturadas como 
`TCustomDaemon` e `TCustomDaemonApplication`.

### 2.5 Políticas de Rotação de Logs com systemd-journald e Logrotate

APIs de alta frequência de requisições geram gigabytes de logs de acesso e 
auditoria em poucos dias. Sem uma política ativa de retenção e expurgo, o 
disco rígido do servidor de produção pode lotar (`No space left on device`), 
causando corrupção no banco de dados Firebird e paralisação dos serviços.

O `systemd-journald` possui controle nativo de retenção em `/etc/systemd/journald.conf`:
- `SystemMaxUse=500M`: Impede que os logs combinados do journal ocupem mais 
  de 500 megabytes no disco.
- `MaxRetentionSec=1month`: Expulga automaticamente entradas com mais de 30 dias.
- `Compress=yes`: Compacta blocos de log antigos em formato binário otimizado.

Caso sua infraestrutura exija arquivos de log tradicionais em texto plano 
(`/var/log/connectos/access.log`), configuramos o utilitário padrão `logrotate` 
para efetuar compressão gzip diária e manter apenas as últimas 14 rotações.

---

## 3. Implementação Passo a Passo

### 3.1 Tratamento de Sinais POSIX no Free Pascal (`Core.Signals.pas`)

No Linux, utilizamos a unit `BaseUnix` para capturar os sinais `SIGTERM` 
e `SIGINT`:

```pascal
unit Core.Signals;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes,
  {$IFDEF UNIX}
  BaseUnix,
  {$ENDIF}
  Horse;

type
  TSignalHandler = class
  private
    class var FFinalizacaoSolicitada: Boolean;
    {$IFDEF UNIX}
    class procedure ManipularSinalPOSIX(ASig: LongInt); cdecl; static;
    {$ENDIF}
  public
    class procedure Inicializar;
    class property FinalizacaoSolicitada: Boolean 
      read FFinalizacaoSolicitada;
  end;

implementation

{$IFDEF UNIX}
class procedure TSignalHandler.
  ManipularSinalPOSIX(ASig: LongInt); cdecl;
begin
  WriteLn(Format('[SINAL RECEBIDO] Sinal POSIX %d capturado.', [ASig]));
  FFinalizacaoSolicitada := True;
  { Solicita encerramento ao Horse }
  try
    THorse.StopListen;
  except
  end;
end;
{$ENDIF}

class procedure TSignalHandler.Inicializar;
{$IFDEF UNIX}
var
  vAcao: SigActionRec;
begin
  FFinalizacaoSolicitada := False;
  FillChar(vAcao, SizeOf(vAcao), 0);
  vAcao.sa_handler := @ManipularSinalPOSIX;

  fpSigAction(SIGTERM, @vAcao, nil);
  fpSigAction(SIGINT, @vAcao, nil);
  WriteLn('[SIGNALS] Handlers de SIGTERM e SIGINT registrados.');
end;
{$ELSE}
begin
  FFinalizacaoSolicitada := False;
end;
{$ENDIF}

end.
```

### 3.2 O Arquivo de Unidade systemd (`connectos-api.service`)

Criamos o arquivo de serviço em `/etc/systemd/system/connectos-api.service`:

```ini
[Unit]
Description=ConnectOS API — Servico de Gestao de OS e Faturamento
After=network.target firebird.service
Wants=network-online.target

[Service]
Type=simple
User=connectos
Group=connectos
WorkingDirectory=/opt/connectos/api
ExecStart=/opt/connectos/api/bin/connect_os_api
ExecReload=/bin/kill -s HUP $MAINPID

# Politica de Reinicializacao Automatica em caso de falha
Restart=always
RestartSec=5s

# Limites de Recursos do Sistema Operacional
LimitNOFILE=65536
LimitNPROC=4096

# Seguranca de Processo e Isolamento
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateTmp=true

# Variaveis de Ambiente de Producao
Environment=PORT=9000
Environment=FB_HOST=localhost
Environment=FB_DATABASE=/opt/connectos/database/CONNECTOS.FDB
Environment=FB_USER=CONNECTOS_APP
Environment=FB_PASS=ChaveForteProducao2026!
Environment=STORAGE_PATH=/opt/connectos/storage

# Logs e Saida Padrao
StandardOutput=journal
StandardError=journal
SyslogIdentifier=connectos-api

[Install]
WantedBy=multi-user.target
```

### 3.3 Provisionamento e Ativação do Serviço no Ubuntu 24.04

Executamos o passo a passo de implantação no servidor Linux:

```bash
# 1. Cria usuario de sistema sem shell de login (seguranca)
sudo useradd -r -s /usr/sbin/nologin -d /opt/connectos connectos

# 2. Cria estrutura de diretorios de producao
sudo mkdir -p /opt/connectos/api/bin
sudo mkdir -p /opt/connectos/storage
sudo mkdir -p /opt/connectos/logs

# 3. Copia o binario compilado de producao
sudo cp bin/connect_os_api /opt/connectos/api/bin/
sudo chmod +x /opt/connectos/api/bin/connect_os_api

# 4. Ajusta permissoes para o usuario dedicado
sudo chown -R connectos:connectos /opt/connectos

# 5. Instala a unidade systemd e recarrega o daemon
sudo cp deploy/connectos-api.service /etc/systemd/system/
sudo systemctl daemon-reload

# 6. Habilita inicializacao no boot do SO e inicia o servico
sudo systemctl enable connectos-api
sudo systemctl start connectos-api
```

### 3.4 Implementando um Windows Service com Lazarus (`lazdaemon`)

Para sistemas Windows, criamos a unit `Daemon.ConnectOS.pas` herdando 
de `TCustomDaemon`:

```pascal
unit Daemon.ConnectOS;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, daemonapp, Horse, Core.ConnectionPool;

type
  TConnectOSDaemon = class(TCustomDaemon)
  public
    function Start: Boolean; override;
    function Stop: Boolean; override;
  end;

implementation

function TConnectOSDaemon.Start: Boolean;
begin
  WriteLn('[WINDOWS SERVICE] Inicializando ConnectOS API...');
  { Horse escutando em segundo plano }
  Result := True;
end;

function TConnectOSDaemon.Stop: Boolean;
begin
  WriteLn('[WINDOWS SERVICE] Finalizando ConnectOS API...');
  try
    THorse.StopListen;
  except
  end;
  Result := True;
end;

end.
```

### 3.5 Instalação e Controle de Windows Service via PowerShell

No Windows Server, instalamos e gerenciamos o serviço via PowerShell 
administrativo:

```powershell
# 1. Registra o servico no Service Control Manager (SCM)
New-Service -Name "ConnectOSAPI" `
    -BinaryPathName "C:\ConnectOS\bin\connect_os_service.exe" `
    -DisplayName "ConnectOS API — Faturamento e OS" `
    -Description "API REST Horse de Alta Performance" `
    -StartupType Automatic

# 2. Inicia o servico imediatamente
Start-Service -Name "ConnectOSAPI"

# 3. Consulta o status operacional
Get-Service -Name "ConnectOSAPI"
```

### 3.6 Script de Healthcheck e Reinicialização Controlada (`graceful_restart.sh`)

Para realizar deploys sem *downtime* perceptível, criamos um script shell 
que verifica a saúde do processo antes e depois da transição de versão:

```bash
#!/usr/bin/env bash
set -e

API_URL="http://localhost:9000/ping"
echo "==> Verificando estado atual da ConnectOS API..."
if curl -s -f -m 3 "${API_URL}" > /dev/null; then
    echo "==> Servico respondendo normalmente. Solicitando restart..."
else
    echo "==> ATENCAO: API nao respondendo antes do restart."
fi

sudo systemctl restart connectos-api

echo "==> Aguardando aquecimento do Pool Firebird..."
for i in {1..10}; do
    if curl -s -f -m 2 "${API_URL}" > /dev/null; then
        echo "==> API reiniciada e pronta com sucesso!"
        exit 0
    fi
    sleep 1
done

echo "==> ERRO: API nao respondeu ao healthcheck apos 10 segundos!"
sudo journalctl -u connectos-api -n 25 --no-pager
exit 1
```

### 3.7 Limites de CPU e Memória via cgroups no systemd

Para impedir que picos de tráfego consumam todos os recursos do servidor e 
prejudiquem o Firebird 5.0, você pode aplicar limites rígidos de cgroups 
diretamente na seção `[Service]` do arquivo de unidade:

```ini
# Limite estrito de Memoria RAM (512 MB)
MemoryMax=512M
MemoryHigh=400M

# Limite de Utilizacao de CPU (200% = maximo de 2 nucleos completos)
CPUQuota=200%
```

Se a aplicação atingir o limite de `MemoryMax`, o kernel Linux ativa o 
OOM-killer apenas sobre as threads excedentes da API, protegendo o sistema 
operacional e os demais serviços hospedeiros.

---

## 4. Testando o Endpoint e Operações do Serviço

Abaixo demonstramos a administração e monitoramento do serviço em produção.

### 4.1 Verificando o Status do Serviço

```bash
sudo systemctl status connectos-api
```

**Saída esperada:**
```text
● connectos-api.service - ConnectOS API — Gestao de OS
     Loaded: loaded (/etc/systemd/system/connectos-api.service; enabled)
     Active: active (running) since Mon 2026-11-23 10:15:00 UTC
   Main PID: 1042 (connect_os_api)
      Tasks: 14 (limit: 4096)
     Memory: 18.4M
        CPU: 1.250s
     CGroup: /system.slice/connectos-api.service
             └─1042 /opt/connectos/api/bin/connect_os_api

Nov 23 10:15:00 srv-prod connectos[1042]: [POOL] 5 conexoes aquecidas.
Nov 23 10:15:00 srv-prod connectos[1042]: [HORSE] Escutando porta 9000.
```

### 4.2 Monitoramento de Logs em Tempo Real com `journalctl`

Para acompanhar os logs gerados pela aplicação e middlewares em tempo real:

```bash
# Acompanhamento continuo (-f) dos logs da API
sudo journalctl -u connectos-api -f

# Filtrando logs apenas das ultimas 2 horas com prioridade de erro
sudo journalctl -u connectos-api --since "2 hours ago" -p err
```

### 4.3 Testando o Encerramento Gracioso e Reinicialização

Simulando o envio de um sinal de encerramento controlado:

```bash
sudo systemctl stop connectos-api
sudo journalctl -u connectos-api -n 10
```

**Logs de encerramento gracioso exibidos:**
```text
Nov 23 12:30:10 srv-prod connectos[1042]: [SINAL] POSIX 15 capturado.
Nov 23 12:30:10 srv-prod connectos[1042]: [HORSE] Fechando escuta...
Nov 23 12:30:11 srv-prod connectos[1042]: [POOL] Fechando conexoes...
Nov 23 12:30:11 srv-prod connectos[1042]: [CONNECTOS] Sucesso.
```

### 4.4 Supervisão Ativa por Watchdog do systemd

Para aplicações de missão crítica onde até mesmo um travamento por deadlock 
de thread deve ser detectado e corrigido automaticamente sem intervenção 
humana, o systemd oferece o mecanismo de **Watchdog de Hardware e Software**:

1. No arquivo `.service`, habilite: `WatchdogSec=30s`.
2. A cada 10 ou 15 segundos, a API Horse envia um sinal de "estou viva" para 
   o socket do systemd chamando a função `sd_notify(0, 'WATCHDOG=1')` da 
   biblioteca `libsystemd0`.
3. Se a aplicação sofrer um travamento completo em todas as threads e não 
   emitir o sinal antes do esgotamento da janela de 30 segundos, o systemd 
   conclui que o processo está congelado (*unresponsive*), emite um sinal 
   `SIGABRT` para salvar um *core dump* de depuração e reinicia o serviço 
   imediatamente.

Esse recurso eleva a resiliência do ecossistema a níveis de alta disponibilidade 
corporativa (*four nines* / 99.99%).

---

## 5. Armadilhas Comuns e Troubleshooting no FPC/Lazarus

### 5.1 O Erro de Inicialização por Diretório de Trabalho Incorreto
Se o arquivo `.service` não declarar `WorkingDirectory=/opt/connectos/api`, 
o systemd iniciará o binário no diretório raiz (`/`). Qualquer tentativa de 
ler arquivos de configuração relativos (`config.json`) ou criar diretórios 
locais falhará com erro `EInOutError: Directory not found`.

### 5.2 O Loop de Falha Rápida (*Start-Limit-Hit*)
Se a aplicação falhar imediatamente na inicialização (por exemplo, porque o 
Firebird 5.0 ainda não estava online ou as credenciais estavam incorretas), 
a diretiva `Restart=always` tentará reiniciar o processo dezenas de vezes em 
segundos. O systemd bloqueará o serviço para proteger o SO:
```text
systemd[1]: connectos-api.service: Start request repeated too quickly.
```
**Solução:** 
1. Sempre defina `RestartSec=5s` para espaçar as tentativas.
2. No `[Unit]`, inclua `After=network.target firebird.service` para garantir 
   que o banco de dados inicialize antes da API.

### 5.3 O Problema da Falta de Liberação de Porta (*SO_REUSEADDR*)
Se a API for encerrada e reiniciada imediatamente, o socket TCP pode 
permanecer em estado `TIME_WAIT` no kernel do Linux por até 60 segundos. 
O `fphttpserver` do Lazarus deve ser configurado com a opção de reuso de 
endereço (`SO_REUSEADDR`), prevenindo o erro `Address already in use`.

### 5.4 Isolamento da Sessão 0 no Windows Server
Desde o Windows Vista e Windows Server 2008, todos os serviços do sistema 
operacional rodam exclusivamente na **Sessão 0**, isolados das sessões 
interativas dos usuários de desktop (Sessão 1, 2, etc.). Qualquer rotina 
que tente invocar caixas de diálogo modais (`ShowMessage`, `MessageDlg`) 
congelará a thread do serviço indefinidamente aguardando um clique que nunca 
poderá ocorrer. Mantenha os serviços do Lazarus estritamente livres de 
qualquer unit da LCL (interface visual).

### 5.5 Sincronização de Fuso Horário e NTP em Logs de Auditoria
Se o relógio do servidor estiver desalinhado ou configurado em fusos 
incompatíveis (por exemplo, o sistema operacional gravando logs no journalctl 
em UTC e o banco Firebird 5.0 operando em Horário de Brasília GMT-3), a 
correlação de incidentes de segurança torna-se caótica.

**Recomendação:** Configure todos os servidores de aplicação e banco para 
o fuso universal UTC com o serviço `systemd-timesyncd` ativado:
```bash
sudo timedatectl set-timezone UTC
sudo timedatectl set-ntp true
```
Dessa forma, todo `TIMESTAMP` gravado no banco ou emitido nos logs segue a 
mesma referência temporal inequívoca.

---

## 6. Resumo Executivo e Checklist de Revisão

Neste módulo, transformamos nossa aplicação Horse em um serviço autônomo de 
nível corporativo, protegido por limites de recursos do Linux e monitorado 
continuamente pelo systemd.

### Checklist de Revisão
- [ ] A unidade `connectos-api.service` reside em `/etc/systemd/system/`?
- [ ] O serviço roda sob usuário de sistema sem permissão de shell (`nologin`)?
- [ ] O limite de descritores de arquivos `LimitNOFILE=65536` está ativado?
- [ ] A política `Restart=always` com `RestartSec=5s` está configurada?
- [ ] Sinais `SIGTERM` e `SIGINT` são interceptados para encerramento gracioso?
- [ ] Os logs são despachados para o `systemd-journald` e auditáveis com `journalctl`?
