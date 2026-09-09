#!/usr/bin/env pwsh
# sync-skills.ps1 -- (re)cria as skills deste repo nos locais que cada CLI de IA espera.
#
# Em vez de link (symlink/junction), copia o conteudo de cada skill -- evita problemas de
# link em Windows (exige admin) e deixa o destino sempre como uma copia fiel e descartavel.
#
# Alvos (parametro -Cli, default "all"):
#   claude  -> copia cada skill (diretorio com SKILL.md na raiz) para ~/.claude/skills/<nome>,
#              apagando e recriando o destino a cada run; remove copias orfas (skill removida do repo).
#   kilo    -> garante que ~/.config/kilo/kilo.jsonc tenha o caminho deste repo em "skills.paths"
#              (o Kilo le os SKILL.md direto da fonte, nao precisa de copia).
#
# Uso:
#   pwsh bin/sync-skills.ps1                  # aplica em claude + kilo
#   pwsh bin/sync-skills.ps1 -Cli claude      # aplica so no Claude Code
#   pwsh bin/sync-skills.ps1 -Cli kilo        # aplica so no Kilo
#   pwsh bin/sync-skills.ps1 -DryRun          # so mostra o que faria
param(
    [ValidateSet("claude", "kilo", "all")]
    [string]$Cli = "all",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$RepoDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Mode = if ($DryRun) { "dry-run" } else { "apply" }

function Get-Skills {
    Get-ChildItem -Path $RepoDir -Directory | Where-Object {
        Test-Path (Join-Path $_.FullName "SKILL.md")
    }
}

function Sync-Claude {
    $targetDir = Join-Path $HOME ".claude\skills"
    if (-not (Test-Path $targetDir) -and $Mode -eq "apply") {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    $skills = Get-Skills
    $skillNames = $skills.Name

    # 1) (Re)cria uma copia fiel de cada skill
    foreach ($skill in $skills) {
        $dest = Join-Path $targetDir $skill.Name
        Write-Output "${Mode}: recria $dest <- $($skill.FullName)"
        if ($Mode -eq "apply") {
            if (Test-Path $dest) { Remove-Item -Path $dest -Recurse -Force }
            Copy-Item -Path $skill.FullName -Destination $dest -Recurse -Force
        }
    }

    # 2) Remove copias orfas (nome nao existe mais como skill no repo)
    if (Test-Path $targetDir) {
        Get-ChildItem -Path $targetDir -Directory | ForEach-Object {
            if ($skillNames -notcontains $_.Name) {
                Write-Output "${Mode}: rm $($_.FullName) (orfao -- $($_.Name) nao e mais skill)"
                if ($Mode -eq "apply") { Remove-Item -Path $_.FullName -Recurse -Force }
            }
        }
    }
}

function Sync-Kilo {
    $configPath = Join-Path $HOME ".config\kilo\kilo.jsonc"
    if (-not (Test-Path $configPath)) {
        Write-Warning "  $configPath nao existe -- pulando configuracao do Kilo."
        return
    }

    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    $repoPathForward = $RepoDir -replace '\\', '/'

    $hasSkills = $null -ne $config.skills
    $paths = if ($hasSkills -and $config.skills.paths) { @($config.skills.paths) } else { @() }

    if ($paths -contains $repoPathForward) {
        Write-Output "kilo.jsonc ja aponta para $repoPathForward -- nada a fazer."
        return
    }

    Write-Output "${Mode}: adiciona '$repoPathForward' em skills.paths de $configPath"
    if ($Mode -ne "apply") { return }

    $paths += $repoPathForward
    if (-not $hasSkills) {
        $config | Add-Member -MemberType NoteProperty -Name "skills" -Value ([PSCustomObject]@{ paths = $paths })
    } else {
        $config.skills.paths = $paths
    }

    $tmp = New-TemporaryFile
    try {
        $config | ConvertTo-Json -Depth 10 | Set-Content -Path $tmp -Encoding utf8
        Copy-Item -Path $tmp -Destination $configPath -Force
    } finally {
        Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
    }
}

if ($Cli -eq "claude" -or $Cli -eq "all") { Sync-Claude }
if ($Cli -eq "kilo" -or $Cli -eq "all") { Sync-Kilo }

Write-Output "Feito ($Mode)."
