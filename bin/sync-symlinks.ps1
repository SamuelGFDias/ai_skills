#!/usr/bin/env pwsh
# sync-symlinks.ps1 -- mantem ~/.claude/skills em paridade com o repo ai_skills (equivalente Windows
# de bin/sync-symlinks.sh). Usa Junctions em vez de symlinks porque criar symlinks reais no Windows
# exige privilegio de administrador (ou Modo de Desenvolvedor); Junctions de diretorio nao exigem.
#
# - Cria uma Junction em ~/.claude/skills/<nome> -> <repo>/<nome> para cada diretorio com SKILL.md.
# - Remove Junctions orfas (apontam para o repo mas o diretorio/SKILL.md nao existe mais).
# - Idempotente; pode rodar a qualquer momento.
#
# Uso:
#   pwsh bin/sync-symlinks.ps1            # aplica (cria + remove)
#   pwsh bin/sync-symlinks.ps1 -DryRun    # so mostra o que faria
param(
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$RepoDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$TargetDir = Join-Path $HOME ".claude\skills"
$Mode = if ($DryRun) { "dry-run" } else { "apply" }

if (-not (Test-Path $TargetDir)) {
    if ($Mode -eq "apply") { New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null }
}

# 1) Cria/atualiza Junctions para cada skill (diretorio com SKILL.md na raiz)
Get-ChildItem -Path $RepoDir -Directory | ForEach-Object {
    $skillDir = $_.FullName
    $skillMd = Join-Path $skillDir "SKILL.md"
    if (-not (Test-Path $skillMd)) { return }

    $name = $_.Name
    $link = Join-Path $TargetDir $name
    $item = Get-Item -Path $link -Force -ErrorAction SilentlyContinue

    if ($item -and $item.LinkType -eq "Junction" -and $item.Target[0] -eq $skillDir) {
        return # ja ok
    }
    if ($item -and $item.LinkType -ne "Junction") {
        Write-Warning "  $link existe e nao e Junction -- pulando (resolver manualmente)."
        return
    }

    Write-Output "${Mode}: junction $link -> $skillDir"
    if ($Mode -eq "apply") {
        if ($item) { $item.Delete() }
        New-Item -ItemType Junction -Path $link -Target $skillDir | Out-Null
    }
}

# 2) Remove Junctions orfas (apontam para dentro do repo, mas o alvo nao e mais skill)
Get-ChildItem -Path $TargetDir -Force -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.LinkType -ne "Junction") { return }
    $target = $_.Target[0]
    if (-not $target.StartsWith($RepoDir)) { return }

    $name = $_.Name
    $skillMd = Join-Path $RepoDir "$name\SKILL.md"
    if (-not (Test-Path $skillMd)) {
        Write-Output "${Mode}: rm $($_.FullName) (orfao -- $name nao e mais skill)"
        if ($Mode -eq "apply") { $_.Delete() }
    }
}

Write-Output "Feito ($Mode)."
