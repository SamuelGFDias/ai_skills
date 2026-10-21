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
#   codex   -> copia (mesmo criterio de claude) cada skill para ~/.agents/skills/<nome> --
#              diretorio de escopo de usuario que o Codex CLI escaneia nativamente (skills
#              auto-descobertas, mesmo formato de SKILL.md com frontmatter name+description).
#   gemini  -> Gemini CLI nao tem diretorio solto de skills: o mecanismo oficial e uma extension
#              em ~/.gemini/extensions/<nome>/ com manifesto gemini-extension.json e as skills
#              dentro de skills/<nome>/SKILL.md da propria extension. Por isso mantemos aqui uma
#              extension propria "ai-skills" em ~/.gemini/extensions/ai-skills/, com manifesto
#              minimo, e sincronizamos as skills para dentro de extensions/ai-skills/skills/.
#
# Nota sobre opencode: NAO tem alvo proprio aqui de proposito. A doc oficial confirma que o
# opencode ja le skills nativamente de ~/.claude/skills/ (compat nativa com Claude Code, ligada
# por padrao, desativavel via OPENCODE_DISABLE_CLAUDE_CODE_SKILLS) -- rodar o alvo "claude" ja e
# suficiente, mesmo em maquina sem o binario `claude` instalado (Sync-Claude so escreve um
# diretorio). Nao recriar um alvo "opencode" aqui.
#
# Uso:
#   pwsh bin/sync-skills.ps1                  # aplica em claude + kilo + codex + gemini
#   pwsh bin/sync-skills.ps1 -Cli claude      # aplica so no Claude Code
#   pwsh bin/sync-skills.ps1 -Cli kilo        # aplica so no Kilo
#   pwsh bin/sync-skills.ps1 -Cli codex       # aplica so no Codex CLI
#   pwsh bin/sync-skills.ps1 -Cli gemini      # aplica so na extension do Gemini CLI
#   pwsh bin/sync-skills.ps1 -DryRun          # so mostra o que faria
param(
    [ValidateSet("claude", "kilo", "codex", "gemini", "all")]
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

function Sync-SkillDirTarget {
    param([string]$TargetDir)

    if (-not (Test-Path $TargetDir) -and $Mode -eq "apply") {
        New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    }

    $skills = Get-Skills
    $skillNames = $skills.Name

    # 1) (Re)cria uma copia fiel de cada skill
    foreach ($skill in $skills) {
        $dest = Join-Path $TargetDir $skill.Name
        Write-Output "${Mode}: recria $dest <- $($skill.FullName)"
        if ($Mode -eq "apply") {
            if (Test-Path $dest) { Remove-Item -Path $dest -Recurse -Force }
            Copy-Item -Path $skill.FullName -Destination $dest -Recurse -Force
        }
    }

    # 2) Remove copias orfas (nome nao existe mais como skill no repo)
    #    "synced" e gerenciado pelo app Claude (skills sincronizadas da conta) -- nunca apagar.
    $protegidos = @("synced")
    if (Test-Path $TargetDir) {
        Get-ChildItem -Path $TargetDir -Directory | ForEach-Object {
            if ($protegidos -contains $_.Name) { return }
            if ($skillNames -notcontains $_.Name) {
                Write-Output "${Mode}: rm $($_.FullName) (orfao -- $($_.Name) nao e mais skill)"
                if ($Mode -eq "apply") { Remove-Item -Path $_.FullName -Recurse -Force }
            }
        }
    }
}

function Sync-Claude {
    Sync-SkillDirTarget (Join-Path $HOME ".claude\skills")
}

function Sync-Codex {
    Sync-SkillDirTarget (Join-Path $HOME ".agents\skills")
}

function Sync-Gemini {
    $extDir = Join-Path $HOME ".gemini\extensions\ai-skills"
    $manifest = Join-Path $extDir "gemini-extension.json"

    if ($Mode -eq "apply") {
        if (-not (Test-Path $extDir)) { New-Item -ItemType Directory -Path $extDir -Force | Out-Null }
        $manifestContent = @'
{
  "name": "ai-skills",
  "version": "1.0.0"
}
'@
        Set-Content -Path $manifest -Value $manifestContent -Encoding utf8
    } else {
        Write-Output "${Mode}: escreveria $manifest"
    }

    Sync-SkillDirTarget (Join-Path $extDir "skills")

    $configDir = Join-Path $HOME ".gemini\config"
    if ($Mode -eq "apply") {
        if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }
        $skillsJsonPath = Join-Path $configDir "skills.json"
        $repoPathForward = $RepoDir -replace '\\', '/'
        $skillsJsonContent = @"
{
  "entries": [
    {
      "path": "$repoPathForward"
    }
  ]
}
"@
        Set-Content -Path $skillsJsonPath -Value $skillsJsonContent -Encoding utf8
    } else {
        Write-Output "${Mode}: escreveria skills.json em $configDir"
    }
    Sync-SkillDirTarget (Join-Path $configDir "skills")
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
if ($Cli -eq "codex" -or $Cli -eq "all") { Sync-Codex }
if ($Cli -eq "gemini" -or $Cli -eq "all") { Sync-Gemini }

Write-Output "Feito ($Mode)."
