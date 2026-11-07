# Runbook — T3 Code remoto no Windows

Este fluxo mantém o servidor T3 em segundo plano após o logon, independente da janela do app desktop. O servidor usa `%USERPROFILE%\.t3-server`; o desktop mantém `%USERPROFILE%\.t3`. O acesso do celular passa apenas pela tailnet do Tailscale.

Execute os comandos em PowerShell. Não fixe hostname nem sufixo de tailnet: descubra ambos pelo Tailscale. Use uma porta livre para o servidor, e escreva-a no lugar de `<PORTA_SERVICO>` nos comandos abaixo.

## 1. Instalar o desktop e o Tailscale

```powershell
winget install --id T3Tools.T3Code --exact --accept-package-agreements --accept-source-agreements
winget install --id Tailscale.Tailscale --exact --accept-package-agreements --accept-source-agreements
```

Abra o Tailscale e autentique a máquina. Abra o T3 Code uma vez para concluir a instalação do app.

## 2. Instalar um CLI independente para o servidor

O launcher do servidor não deve ficar dentro do diretório de dados do desktop.

```powershell
$env:T3CODE_HOME = Join-Path $env:USERPROFILE '.t3-server'
$env:T3CODE_INSTALL_BIN_DIR = Join-Path $env:USERPROFILE '.local\bin'
# Opcional: fixe a versão. Sem a variável, o instalador usa a versão padrão dele.
# $env:T3CODE_VERSION = '<versão>'
irm https://t3.codes/install.ps1 | iex
& (Join-Path $env:T3CODE_INSTALL_BIN_DIR 't3.cmd') --version
```

Acrescente `%USERPROFILE%\.local\bin` ao `PATH` do usuário se o instalador ainda não tiver feito isso. Acrescente também o diretório de instalação do Tailscale se `tailscale version` não funcionar em um terminal novo.

## 3. Criar o launcher persistente

Crie `%USERPROFILE%\.t3-server\start-t3-server.ps1`:

```powershell
$ErrorActionPreference = 'Stop'

$t3Launcher = Join-Path $env:USERPROFILE '.local\bin\t3.cmd'
$serverHome = Join-Path $env:USERPROFILE '.t3-server'

& $t3Launcher serve `
    --base-dir $serverHome `
    --host 127.0.0.1 `
    --port <PORTA_SERVICO>

exit $LASTEXITCODE
```

Não adicione `--tailscale-serve` ao launcher. A autorização e o proxy do Tailscale são configurados uma única vez no passo 5.

## 4. Registrar a Tarefa Agendada

```powershell
$taskName = 'T3 Code Headless Server'
$scriptPath = Join-Path $env:USERPROFILE '.t3-server\start-t3-server.ps1'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force
Start-ScheduledTask -TaskName $taskName
```

Confirme que a tarefa está `Running` e que a porta é exclusivamente loopback:

```powershell
Get-ScheduledTask -TaskName 'T3 Code Headless Server' | Select-Object TaskName, State
Get-NetTCPConnection -State Listen -LocalPort <PORTA_SERVICO> | Select-Object LocalAddress, LocalPort, OwningProcess
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:<PORTA_SERVICO>/.well-known/v3/environment
```

## 5. Publicar somente na tailnet

```powershell
tailscale status --self
tailscale serve --bg --https=443 --yes http://127.0.0.1:<PORTA_SERVICO>
tailscale serve status
```

Na primeira execução, o Tailscale pode imprimir uma URL de autorização. Abra-a, habilite HTTPS e mantenha **Funnel desligado**. Repita o comando `serve` depois da autorização se o mapeamento ainda não aparecer.

Descubra e teste o nome exato:

```powershell
$tailscaleStatus = tailscale status --json | ConvertFrom-Json
$dnsName = $tailscaleStatus.Self.DNSName.TrimEnd('.')
Invoke-WebRequest -UseBasicParsing "https://$dnsName/.well-known/v3/environment"
```

Esperado: HTTP 200. Não use IP Tailscale para HTTPS, pois o certificado é emitido para o nome DNS.

## 6. Parear o celular e o desktop

Gere um código novo para cada cliente:

```powershell
$t3 = Join-Path $env:USERPROFILE '.local\bin\t3.cmd'
& $t3 pair --base-dir (Join-Path $env:USERPROFILE '.t3-server') --label '<rótulo-do-celular>' --ttl 15m
& $t3 pair --base-dir (Join-Path $env:USERPROFILE '.t3-server') --label '<rótulo-do-desktop>' --ttl 15m
```

- Celular: com o Tailscale conectado à mesma tailnet, prefira o QR/link completo gerado pelo comando. Se preencher manualmente, use `https://<Self.DNSName>` e o código correspondente.
- Desktop: em **Settings → Connections → Add environment**, use `http://127.0.0.1:<PORTA_SERVICO>` e o código do desktop.
- Envie uma mensagem de teste nos dois clientes. Só então desligue **Local environment / Run agents on this computer** no desktop.

Liste as sessões sem expor tokens:

```powershell
& $t3 auth session list --base-dir (Join-Path $env:USERPROFILE '.t3-server')
```

## 7. Diagnóstico final

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <skill>\scripts\diagnostico-windows.ps1 -Port <PORTA_SERVICO> [-ClientName <nome-do-celular>]
```

O diagnóstico deve terminar sem `[ATENCAO]`. Reinicie manualmente a tarefa uma vez e confirme que o PID muda, a porta volta a escutar e os dois clientes continuam conectando.

## Limites e segurança

- A tarefa inicia no logon, não antes dele.
- O listener do T3 permanece em `127.0.0.1`; não abra a porta no firewall/LAN.
- `tailscale serve` é tailnet-only. Não habilite Funnel.
- Códigos de pareamento expiram e devem ser gerados novamente quando necessário; nunca os versione.
- Não rode `t3 uninstall` para trocar de versão. Use [07-upgrade-versao.md](07-upgrade-versao.md).
