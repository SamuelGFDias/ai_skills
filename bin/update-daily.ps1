#!/usr/bin/env pwsh
# update-daily.ps1 -- rotina do repo de skills no Windows: `git pull --ff-only` em todos os
# remotes e, quando algo mudou, `bin\install.ps1` para propagar skills/subagentes/instrucoes
# globais para os CLIs desta maquina. Escreve um log por execucao.
#
# Equivalente ao bin/update-daily.sh. No Windows nao ha cron de usuario: a rotina fica no
# Agendador de Tarefas (uma unica tarefa "ai-skills update-daily", reinstalar substitui, nunca
# duplica) rodando `pwsh -NoProfile -File bin\update-daily.ps1`.
#
# Regras iguais ao .sh: nunca pergunta nada, nunca commita, nunca faz merge/rebase (pull --ff-only
# falha se o historico divergir, e o log registra), nao roda nenhum CLI de IA.
#
# Log: %LOCALAPPDATA%\ai-skills\update-daily.log (AI_SKILLS_LOG_DIR muda a pasta).
#   Rotacao: AI_SKILLS_LOG_MAX_BYTES (default 1 MiB), uma geracao (.1).
#
# Uso:
#   pwsh bin\update-daily.ps1                     # update + sync se mudou
#   pwsh bin\update-daily.ps1 -DryRun             # so mostra o que faria
#   pwsh bin\update-daily.ps1 -NoSync             # so atualiza o repo
#   pwsh bin\update-daily.ps1 -Status             # ultimo log + estado da tarefa
#   pwsh bin\update-daily.ps1 -Install            # registra/atualiza a tarefa diaria
#   pwsh bin\update-daily.ps1 -Uninstall          # remove a tarefa diaria
#
# Configuracao (parametros; a variavel de ambiente equivalente tem prioridade quando presente):
#   -Time HH:MM      AI_SKILLS_UPDATE_TIME        hora            default 09:00
#   -Days 1-5        AI_SKILLS_UPDATE_DAYS        dias 0-6, */lista default * (todos)
#   -NoSync          AI_SKILLS_UPDATE_SYNC=0      nao roda install  default sync ligado
param(
    [switch]$DryRun,
    [switch]$NoSync,
    [switch]$Status,
    [switch]$Install,
    [switch]$Uninstall,
    [string]$Time = "09:00",
    [string]$Days = "*"
)

$ErrorActionPreference = "Stop"
$RepoDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ScriptPath = Join-Path $RepoDir "bin\update-daily.ps1"
$TaskName = "ai-skills update-daily"

if ($env:AI_SKILLS_UPDATE_TIME) { $Time = $env:AI_SKILLS_UPDATE_TIME }
if ($env:AI_SKILLS_UPDATE_DAYS) { $Days = $env:AI_SKILLS_UPDATE_DAYS }
if ($env:AI_SKILLS_UPDATE_SYNC -eq "0") { $NoSync = $true }

$LogDir = if ($env:AI_SKILLS_LOG_DIR) { $env:AI_SKILLS_LOG_DIR } else { Join-Path $env:LOCALAPPDATA "ai-skills" }
$LogFile = Join-Path $LogDir "update-daily.log"
$LogMaxBytes = if ($env:AI_SKILLS_LOG_MAX_BYTES) { [int]$env:AI_SKILLS_LOG_MAX_BYTES } else { 1048576 }
$DoSync = -not $NoSync

function Write-Log([string]$Message) { Write-Output ">> $Message" }

function Test-TimeValue([string]$Value) {
    return ($Value -match '^([01]?[0-9]|2[0-3]):([0-5][0-9])$')
}

function Test-DaysValue([string]$Value) {
    if ($Value -eq "*") { return $true }
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    # Formato inteiro antes do split: "1-5," ou ",1" nao podem passar.
    if ($Value -notmatch '^[0-6](,[0-6])*$' -and $Value -notmatch '^[0-6]-[0-6](,[0-6](-[0-6])?)*$') { return $false }
    foreach ($part in $Value.Split(',')) {
        if ($part -match '^([0-6])-([0-6])$' -and [int]$Matches[1] -gt [int]$Matches[2]) { return $false }
    }
    return $true
}

# Converte "1-5"/"0,6" para os dias de semana do Task Scheduler (Sunday=0..Saturday=6).
function ConvertTo-TaskDays([string]$Value) {
    if ($Value -eq "*") { return @() }
    $set = New-Object System.Collections.Generic.HashSet[int]
    foreach ($part in $Value.Split(',')) {
        if ($part -match '^([0-6])-([0-6])$') {
            for ($i = [int]$Matches[1]; $i -le [int]$Matches[2]; $i++) { $set.Add($i) | Out-Null }
        } else {
            $set.Add([int]$part) | Out-Null
        }
    }
    $names = @("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")
    return @($set | Sort-Object | ForEach-Object { $names[$_] })
}

# ---------------- Status ----------------

if ($Status) {
    Write-Output "Log: $LogFile"
    if (Test-Path $LogFile) {
        Write-Output "----- ultimas execucoes -----"
        Get-Content $LogFile -Tail 40
    } else {
        Write-Output "(nenhuma execucao registrada ainda)"
    }
    Write-Output ""
    Write-Output "----- rotina instalada -----"
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        $info = Get-ScheduledTaskInfo -TaskName $TaskName
        $trigger = ($task.Triggers | Where-Object { $_.Enabled } | Select-Object -First 1)
        $when = if ($trigger) { "as $($trigger.StartBoundary) ($($trigger.DaysOfWeek))" } else { "sem trigger ativo" }
        Write-Output "$TaskName -- $($task.State) -- $when"
        Write-Output "ultima: $($info.LastRunTime) ($($info.LastTaskResult)) -- proxima: $($info.NextRunTime)"
    } else {
        Write-Output "(nenhuma rotina instalada -- rode: pwsh bin\update-daily.ps1 -Install)"
    }
    Write-Output ""
    Write-Output "----- repo -----"
    git -C $RepoDir status --short --branch
    exit 0
}

# ---------------- Instalacao da rotina ----------------

if ($Install -or $Uninstall) {
    if (-not (Test-TimeValue $Time)) { Write-Output "ERRO: hora invalida: '$Time' (use HH:MM, 00:00-23:59)"; exit 2 }
    if (-not (Test-DaysValue $Days)) { Write-Output "ERRO: dias invalidos: '$Days' (use * ou combinacao de 0-6, ex.: 1-5, 1,3,5)"; exit 2 }

    if ($Install) {
        if (-not (Test-Path $ScriptPath)) { Write-Output "ERRO: $ScriptPath nao existe"; exit 2 }
        Write-Log "registrando tarefa diaria: hora=$Time dias=$Days sync=$DoSync"
    } else {
        Write-Log "removendo a tarefa '$TaskName' do Agendador de Tarefas"
    }

    if ($DryRun) {
        Write-Log "(dry-run) nada foi alterado"
        if ($Install) {
            Write-Log "registraria a tarefa '$TaskName' ($Time, dias: $Days) executando: pwsh -NoProfile -File `"$ScriptPath`""
        } else {
            Write-Log "removeria a tarefa '$TaskName'"
        }
        exit 0
    }

    if ($Uninstall) {
        if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            Write-Log "tarefa removida"
        } else {
            Write-Log "nada para remover (tarefa nao existe)"
        }
        exit 0
    }

    $pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $pwshPath) { Write-Output "ERRO: pwsh nao encontrado no PATH"; exit 2 }
    $taskArgs = "-NoProfile -File `"$ScriptPath`""
    if (-not $DoSync) { $taskArgs += " -NoSync" }
    $action = New-ScheduledTaskAction -Execute $pwshPath -Argument $taskArgs -WorkingDirectory $RepoDir

    [datetime]$at = [datetime]::ParseExact($Time, "HH:mm", [System.Globalization.CultureInfo]::InvariantCulture)
    $at = (Get-Date).Date.Add($at.TimeOfDay)
    $taskDays = ConvertTo-TaskDays $Days
    $trigger = if ($taskDays.Count -eq 0) {
        New-ScheduledTaskTrigger -Daily -At $at
    } else {
        New-ScheduledTaskTrigger -Weekly -DaysOfWeek $taskDays -At $at
    }

    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 15) -MultipleInstances IgnoreNew
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
    Write-Log "tarefa '$TaskName' registrada ($Time, dias: $Days, sync: $DoSync)"
    Write-Log "confira: pwsh bin\update-daily.ps1 -Status   |   log: $LogFile"
    exit 0
}

# ---------------- Update ----------------

if (-not (Test-Path (Join-Path $RepoDir ".git"))) { Write-Output "ERRO: $RepoDir nao e um repositorio git"; exit 2 }
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

if (Test-Path $LogFile) {
    if ((Get-Item $LogFile).Length -gt $LogMaxBytes) {
        Move-Item -Path $LogFile -Destination "$LogFile.1" -Force
    }
}

$Mode = if ($DryRun) { "dry-run" } else { "apply" }
Write-Output "" | Out-File -FilePath $LogFile -Append -Encoding utf8
$header = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')] update-daily ($Mode) repo=$RepoDir sync=$DoSync"
$header | Out-File -FilePath $LogFile -Append -Encoding utf8
Write-Output $header

$exitCode = 0
$pushed = $false
try {
    Push-Location $RepoDir
    $pushed = $true

    # Remotes com refspec de fetch.
    $remotes = @()
    (git config --get-regexp '^remote\..*\.fetch$') | ForEach-Object {
        if ($_ -match '^remote\.(.*)\.fetch') { $remotes += $Matches[1] }
    }
    if ($remotes.Count -eq 0) {
        Write-Log "nenhum remote com fetch configurado -- nada a fazer"
    } else {
        $branch = git rev-parse --abbrev-ref HEAD
        if ($branch -eq "HEAD") {
            Write-Log "ERRO: HEAD destacado (detached); ajuste para uma branch"
            $exitCode = 1
        } else {
            if (git status --porcelain) {
                Write-Log "AVISO: working tree tem alteracoes locais; pull --ff-only vai abortar se conflitarem com o remoto"
            }

            $fetchFailed = $false
            if ($DryRun) {
                Write-Log "git fetch --all --prune --dry-run"
                git fetch --all --prune --dry-run
            } else {
                Write-Log "git fetch --all --prune"
                git fetch --all --prune
                if ($LASTEXITCODE -ne 0) {
                    Write-Log "ERRO: fetch falhou (rede? credencial?). Nada foi alterado."
                    $fetchFailed = $true
                    $exitCode = 1
                }
            }

            if (-not $fetchFailed) {
                $prevHead = git rev-parse HEAD
                $changed = ""
                $anyFail = 0
                $summary = @()

                foreach ($r in $remotes) {
                    $remoteRef = "refs/remotes/$r/$branch"
                    git rev-parse --verify --quiet $remoteRef | Out-Null
                    if ($LASTEXITCODE -ne 0) {
                        $summary += "$r`: branch '$branch' nao existe nesse remote -- ignorado"
                        continue
                    }

                    if ($DryRun) {
                        $counts = (git rev-list --left-right --count "HEAD...$remoteRef") -split "`t"
                        $summary += "$r`: local esta $($counts[0]) a frente, $($counts[1]) atras de $remoteRef (dry-run, sem pull)"
                        if ([int]$counts[1] -gt 0) { $changed = $r }
                        continue
                    }

                    Write-Log "git pull --ff-only $r $branch"
                    git pull --ff-only $r $branch
                    if ($LASTEXITCODE -eq 0) {
                        $after = git rev-parse HEAD
                        if ($prevHead -ne $after) {
                            $changed = $r
                            $summary += "$r`: atualizado $($prevHead.Substring(0,8))..$($after.Substring(0,8))"
                            $prevHead = $after
                        } else {
                            $summary += "$r`: ja estava em dia"
                        }
                    } else {
                        $anyFail++
                        $summary += "$r`: falhou (historico divergente ou alteracao local em conflito) -- resolva manualmente e rode de novo"
                    }
                }

                Write-Log "resumo por remote:"
                foreach ($line in $summary) { Write-Log "  $line" }

                if ($anyFail -gt 0) {
                    Write-Log "ERRO: $anyFail remote(s) falharam; install.ps1 NAO sera executado"
                    $exitCode = 1
                } elseif (-not $changed) {
                    Write-Log "hook: nada novo -- install.ps1 nao e necessario"
                } elseif (-not $DoSync) {
                    Write-Log "hook: mudou ($changed), mas o sync esta desligado (-NoSync / AI_SKILLS_UPDATE_SYNC=0)"
                } else {
                    Write-Log "hook: mudou ($changed) -- rodando bin\install.ps1"
                    if ($DryRun) {
                        pwsh (Join-Path $RepoDir "bin\install.ps1") -DryRun -NoSchedule
                        Write-Log "install.ps1 executado em dry-run (nenhuma alteracao feita)"
                    } else {
                        pwsh (Join-Path $RepoDir "bin\install.ps1") -NoSchedule
                        if ($LASTEXITCODE -ne 0) { Write-Log "ERRO: install.ps1 falhou ($LASTEXITCODE)"; $exitCode = 1 }
                    }
                }
            }
        }
    }
} catch {
    Write-Log "ERRO: $($_.Exception.Message)"
    $exitCode = 1
} finally {
    if ($pushed) { Pop-Location -ErrorAction SilentlyContinue }
    $status = if ($exitCode -eq 0) { "ok" } else { "FALHOU (exit $exitCode)" }
    $footer = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')] fim: $status"
    $footer | Out-File -FilePath $LogFile -Append -Encoding utf8
    Write-Output $footer
}
exit $exitCode
