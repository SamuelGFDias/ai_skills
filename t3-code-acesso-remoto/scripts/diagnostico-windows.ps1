[CmdletBinding()]
param(
    [string]$TaskName = 'T3 Code Headless Server',
    [string]$ServerHome = (Join-Path $env:USERPROFILE '.t3-server'),
    [Parameter(Mandatory)][int]$Port,
    [string]$ClientName
)

$ErrorActionPreference = 'Stop'
$warnings = 0

function Write-Ok([string]$Message) {
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-WarningResult([string]$Message) {
    $script:warnings++
    Write-Host "[ATENCAO] $Message" -ForegroundColor Yellow
}

function Write-InfoResult([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

try {
    $task = Get-ScheduledTask -TaskName $TaskName
    $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName
    if ($task.State -eq 'Running') {
        Write-Ok "Tarefa '$TaskName' em execução (LastTaskResult=$($taskInfo.LastTaskResult))."
    } else {
        Write-WarningResult "Tarefa '$TaskName' está $($task.State); LastTaskResult=$($taskInfo.LastTaskResult)."
    }
} catch {
    Write-WarningResult "Tarefa '$TaskName' não encontrada: $($_.Exception.Message)"
}

$escapedHome = [regex]::Escape($ServerHome)
$serverProcesses = @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -eq 't3.exe' -and $_.CommandLine -match $escapedHome
})
if ($serverProcesses.Count -eq 1) {
    Write-Ok "Um processo t3.exe usa o diretório isolado '$ServerHome' (PID $($serverProcesses[0].ProcessId))."
} elseif ($serverProcesses.Count -eq 0) {
    Write-WarningResult "Nenhum processo t3.exe usa '$ServerHome'."
} else {
    Write-WarningResult "Mais de um processo t3.exe usa '$ServerHome': $($serverProcesses.ProcessId -join ', ')."
}

$listeners = @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
if ($listeners.Count -eq 1 -and $listeners[0].LocalAddress -in @('127.0.0.1', '::1')) {
    Write-Ok "Porta $Port escuta somente em loopback ($($listeners[0].LocalAddress), PID $($listeners[0].OwningProcess))."
} elseif ($listeners.Count -eq 0) {
    Write-WarningResult "Nenhum listener encontrado na porta $Port."
} else {
    Write-WarningResult "Listener inesperado na porta ${Port}: $($listeners.LocalAddress -join ', ')."
}

$localEndpoint = "http://127.0.0.1:$Port/.well-known/v3/environment"
try {
    $localResponse = Invoke-WebRequest -UseBasicParsing -Uri $localEndpoint -TimeoutSec 10
    if ($localResponse.StatusCode -eq 200) {
        Write-Ok "Endpoint local respondeu HTTP 200."
    } else {
        Write-WarningResult "Endpoint local respondeu HTTP $($localResponse.StatusCode)."
    }
} catch {
    Write-WarningResult "Endpoint local falhou: $($_.Exception.Message)"
}

$tailscale = Get-Command tailscale.exe -ErrorAction SilentlyContinue
if (-not $tailscale) {
    $fallback = 'C:\Program Files\Tailscale\tailscale.exe'
    if (Test-Path -LiteralPath $fallback) {
        $tailscalePath = $fallback
        Write-Ok "Tailscale encontrado no caminho padrão: $fallback"
        Write-InfoResult 'Este processo ainda não recebeu a atualização do PATH; abra um terminal novo se quiser usar apenas o nome tailscale.'
    } else {
        Write-WarningResult 'tailscale.exe não foi encontrado.'
        $tailscalePath = $null
    }
} else {
    $tailscalePath = $tailscale.Source
    Write-Ok "Tailscale encontrado no PATH: $tailscalePath"
}

if ($tailscalePath) {
    try {
        $status = (& $tailscalePath status --json | ConvertFrom-Json)
        if ($status.BackendState -eq 'Running' -and $status.Self.Online) {
            Write-Ok 'Tailscale está Running e o nó está online.'
        } else {
            Write-WarningResult "Tailscale BackendState=$($status.BackendState), Online=$($status.Self.Online)."
        }

        $dnsName = [string]$status.Self.DNSName
        $dnsName = $dnsName.TrimEnd('.')
        if ($dnsName) {
            Write-Ok "Nome DNS descoberto: $dnsName"
            $serveStatus = (& $tailscalePath serve status 2>&1 | Out-String)
            if ($serveStatus -match [regex]::Escape("127.0.0.1:$Port")) {
                Write-Ok "Tailscale Serve encaminha para 127.0.0.1:$Port."
            } else {
                Write-WarningResult "Tailscale Serve não aponta para 127.0.0.1:$Port."
            }

            try {
                $remoteResponse = Invoke-WebRequest -UseBasicParsing -Uri "https://$dnsName/.well-known/v3/environment" -TimeoutSec 15
                if ($remoteResponse.StatusCode -eq 200) {
                    Write-Ok 'Endpoint HTTPS da tailnet respondeu HTTP 200.'
                } else {
                    Write-WarningResult "Endpoint HTTPS respondeu HTTP $($remoteResponse.StatusCode)."
                }
            } catch {
                Write-WarningResult "Endpoint HTTPS falhou: $($_.Exception.Message)"
            }
        } else {
            Write-WarningResult 'Self.DNSName não foi informado pelo Tailscale.'
        }

        if ($ClientName) {
            $pingOutput = (& $tailscalePath ping --timeout=10s $ClientName 2>&1 | Out-String)
            if ($LASTEXITCODE -eq 0) {
                Write-Ok "Cliente '$ClientName' respondeu ao tailscale ping."
            } else {
                Write-WarningResult "Cliente '$ClientName' não respondeu: $($pingOutput.Trim())"
            }
        }
    } catch {
        Write-WarningResult "Falha ao consultar o Tailscale: $($_.Exception.Message)"
    }
}

$desktopHome = Join-Path $env:USERPROFILE '.t3'
if ([System.IO.Path]::GetFullPath($desktopHome) -ne [System.IO.Path]::GetFullPath($ServerHome)) {
    Write-Ok "Desktop ('$desktopHome') e servidor ('$ServerHome') usam diretórios distintos."
} else {
    Write-WarningResult 'Desktop e servidor apontam para o mesmo diretório de dados.'
}

if ($warnings -gt 0) {
    Write-Host "Diagnóstico concluído com $warnings atenção(ões)." -ForegroundColor Yellow
    exit 1
}

Write-Host 'Diagnóstico concluído sem alertas.' -ForegroundColor Green
exit 0
