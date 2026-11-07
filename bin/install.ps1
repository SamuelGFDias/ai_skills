#!/usr/bin/env pwsh
# install.ps1 -- configura tudo que e necessario para as skills deste repo funcionarem
# em qualquer CLI de IA instalado nesta maquina (claude, kilo, codex, gemini, opencode).
#
# Mesma logica do install.sh (ver comentarios la para detalhes completos por CLI).
# sync-agents.sh e bash-only (ver AGENTS.md, secao "Armadilhas no Windows") -- por isso
# e sempre chamado via `bash`, mesmo neste script PowerShell.
#
# Rotina: no Windows nao ha cron de usuario; a rotina de `git pull` + re-sync fica numa tarefa do
# Agendador de Tarefas, mantida por bin\update-daily.ps1. Este script registra/atualiza a MESMA
# tarefa a cada run (nunca duplica). Parametros: -Time HH:MM (default 09:00), -Days 0-6/*/lista
# (default *), -NoSync (nao roda sync apos pull) e -Schedule (liga a rotina; opt-in, desligada por padrao) e -NoSchedule (nao mexe na rotina). Log em
# %LOCALAPPDATA%\ai-skills\update-daily.log. -Uninstall remove a tarefa; -Status mostra o log.
#
# Uso:
#   pwsh bin/install.ps1
#   pwsh bin/install.ps1 -DryRun
#   pwsh bin/install.ps1 -Schedule -Time 07:30 -Days 1-5
#   pwsh bin/install.ps1 -Schedule
#   pwsh bin/install.ps1 -NoSchedule
#   pwsh bin/install.ps1 -Uninstall
#   pwsh bin/install.ps1 -Status
param(
    [switch]$DryRun,
    [switch]$Schedule,
    [switch]$NoSchedule,
    [switch]$NoSync,
    [switch]$Uninstall,
    [switch]$Status,
    [string]$Time = "09:00",
    [string]$Days = "*"
)

$ErrorActionPreference = "Stop"
$RepoDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Mode = if ($DryRun) { "dry-run" } else { "apply" }

$AllClis = @("claude", "kilo", "codex", "gemini", "opencode")
$Found = @()
$Missing = @()
$ClaudeSkillsSynced = $false
$UpdateDaily = Join-Path $RepoDir "bin\update-daily.ps1"

# Rotina diaria: delegada a bin\update-daily.ps1 (la ficam Agendador, log, status).
function Invoke-DailyUpdate([string[]]$ExtraArgs) {
    if (-not (Test-Path $UpdateDaily)) {
        Write-Warning "bin\update-daily.ps1 ausente -- rotina diaria nao registrada."
        return 0
    }
    $dailyArgs = @("-NoProfile", "-File", $UpdateDaily) + $ExtraArgs
    & pwsh @dailyArgs
    return $LASTEXITCODE
}

function Test-CliExists([string]$Name) {
    if ($Name -eq "gemini") {
        return ($null -ne (Get-Command "gemini" -ErrorAction SilentlyContinue) -or $null -ne (Get-Command "agy" -ErrorAction SilentlyContinue))
    }
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Sync-SkillsFor([string]$Cli) {
    if ($DryRun) {
        Write-Output ">> bin\sync-skills.ps1 -Cli $Cli -DryRun"
        pwsh (Join-Path $RepoDir "bin\sync-skills.ps1") -Cli $Cli -DryRun
    } else {
        Write-Output ">> bin\sync-skills.ps1 -Cli $Cli"
        pwsh (Join-Path $RepoDir "bin\sync-skills.ps1") -Cli $Cli
    }
    if ($Cli -eq "claude") { $script:ClaudeSkillsSynced = $true }
}

function Sync-AgentsFor([string]$Cli) {
    if ($DryRun) {
        Write-Output ">> bash arquiteto/bin/sync-agents.sh $Cli --dry-run"
        bash "arquiteto/bin/sync-agents.sh" $Cli --dry-run
    } else {
        Write-Output ">> bash arquiteto/bin/sync-agents.sh $Cli"
        bash "arquiteto/bin/sync-agents.sh" $Cli
    }
}

function Set-OpencodeDeepseekDefault {
    $configDir = Join-Path $HOME ".config\opencode"
    $configPath = Join-Path $configDir "opencode.jsonc"

    if (-not (Test-Path $configPath)) {
        Write-Output ">> opencode: criando $configPath com modelo default DeepSeek"
        if ($Mode -eq "apply") {
            if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }
            $content = @'
{
  "$schema": "https://opencode.ai/config.json",
  "model": "deepseek/deepseek-v4-flash"
}
'@
            Set-Content -Path $configPath -Value $content -Encoding utf8
        }
        return
    }

    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
    } catch {
        Write-Warning "  Nao foi possivel interpretar $configPath como JSON (pode ter comentarios JSONC) -- nao foi possivel checar/definir o modelo default. Edite manualmente se necessario."
        return
    }

    if ($null -ne $config.model) {
        Write-Output ">> opencode: $configPath ja tem `"model`" definido -- nao sobrescrevendo."
        return
    }

    Write-Output ">> opencode: adicionando `"model`": `"deepseek/deepseek-v4-flash`" em $configPath"
    if ($Mode -ne "apply") { return }

    $config | Add-Member -MemberType NoteProperty -Name "model" -Value "deepseek/deepseek-v4-flash"
    $tmp = New-TemporaryFile
    try {
        $config | ConvertTo-Json -Depth 10 | Set-Content -Path $tmp -Encoding utf8
        Copy-Item -Path $tmp -Destination $configPath -Force
    } finally {
        Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
    }
}

Write-Output "=== install.ps1 -- detectando CLIs instalados ==="

if ($Uninstall) {
    Write-Output "=== rotina diaria (Agendador de Tarefas) ==="
    $extra = @("-Uninstall", "-Time", $Time, "-Days", $Days)
    if ($DryRun) { $extra += "-DryRun" }
    exit (Invoke-DailyUpdate $extra)
}

if ($Status) {
    exit (Invoke-DailyUpdate @("-Status", "-Time", $Time, "-Days", $Days))
}

foreach ($cli in $AllClis) {
    if (Test-CliExists $cli) { $Found += $cli } else { $Missing += $cli }
}

$foundText = if ($Found.Count -gt 0) { $Found -join ", " } else { "nenhum" }
$missingText = if ($Missing.Count -gt 0) { $Missing -join ", " } else { "nenhum" }
Write-Output "Detectados: $foundText"
Write-Output "Nao encontrados: $missingText"
Write-Output ""

if ($Schedule -and -not $NoSchedule) {
    Write-Output "=== rotina diaria (git pull + re-sync via Agendador de Tarefas) ==="
    $extra = @("-Install", "-Time", $Time, "-Days", $Days)
    if ($DryRun) { $extra += "-DryRun" }
    if ($NoSync) { $extra += "-NoSync" }
    $code = Invoke-DailyUpdate $extra
    if ($code -ne 0) {
        Write-Warning "nao foi possivel registrar a rotina diaria (exit $code); o restante do install continua."
    }
    Write-Output ""
}

if ($Found.Count -eq 0) {
    Write-Output "Nenhum CLI de IA suportado (claude|kilo|codex|gemini|opencode) encontrado no PATH. Nada mais a fazer."
    exit 0
}

foreach ($cli in $Found) {
    Write-Output "--- $cli ---"
    switch ($cli) {
        { $_ -in "claude", "kilo", "codex", "gemini" } {
            Sync-SkillsFor $cli
            Sync-AgentsFor $cli
        }
        "opencode" {
            Sync-AgentsFor "opencode"
            if (-not $ClaudeSkillsSynced) {
                Write-Output ">> opencode le skills nativamente de ~/.claude/skills (compat Claude Code) -- sincronizando esse diretorio mesmo sem o binario claude instalado"
                Sync-SkillsFor "claude"
            }
            Set-OpencodeDeepseekDefault
        }
    }
    Write-Output ""
}

Write-Output "=== dist/ dos subagentes (informativo -- nao regenerado por este script) ==="
if (Test-CliExists "python3") {
    python3 (Join-Path $RepoDir "arquiteto\bin\build-agents.py") --check
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "arquiteto/dist/ esta desatualizado em relacao a roles/+models.json. Isso e responsabilidade de quem mantem o repo (rodar build-agents.py e commitar dist/), nao deste install.ps1."
    }
} else {
    Write-Warning "python3 nao encontrado -- nao foi possivel checar drift de arquiteto/dist/."
}

Write-Output ""
Write-Output "Feito ($Mode). CLIs configurados: $($Found -join ', ')."
