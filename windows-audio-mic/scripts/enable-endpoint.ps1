<#
.SYNOPSIS
  Habilita um endpoint de captura de audio DESABILITADO no Windows (exige admin).

.DESCRIPTION
  Grava DeviceState = 268435457 (ATIVO|padrao) em
  HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Capture\{Id} e reinicia o
  servico AudioEndpointBuilder para o Windows recarregar o estado.

  Use SOMENTE para endpoints com estado 2 (DESABILITADO) no diagnostico do audio-mic.ps1.
  Endpoints em estado 4 (NAO_PRESENTE) ou 8 (DESCONECTADO) nao podem ser habilitados por aqui —
  o dispositivo fisico precisa estar conectado.

.PARAMETER Id
  GUID do endpoint. Aceita "{65226944-9ccd-440e-92a7-f14fab5788be}" ou o id completo
  "{0.0.1.00000000}.{65226944-9ccd-440e-92a7-f14fab5788be}". Se omitido, lista os candidatos.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File enable-endpoint.ps1
  powershell -ExecutionPolicy Bypass -File enable-endpoint.ps1 -Id "{65226944-9ccd-440e-92a7-f14fab5788be}"
#>
[CmdletBinding()]
param(
    [string]$Id
)

$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERRO: este script exige privilegios de administrador (UAC)." -ForegroundColor Red
    exit 1
}

$base = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Capture"
$pName = '{a45c254e-df1c-4efd-8020-67d146a850e0},2'

function Get-FriendlyName([string]$guid) {
    $pp = Join-Path $base "$guid\Properties"
    $o1 = Get-ItemProperty -Path $pp -Name $pName -ErrorAction SilentlyContinue
    if ($o1) { $o1.$pName } else { '?' }
}

if (-not $Id) {
    Write-Host "Endpoints de captura e estado (1=ATIVO, 2=DESABILITADO, 4=NAO_PRESENTE, 8=DESCONECTADO):"
    Get-ChildItem $base | ForEach-Object {
        $guid = $_.PSChildName
        $st = (Get-ItemProperty $_.PSPath -Name DeviceState -ErrorAction SilentlyContinue).DeviceState
        Write-Host ("  {0} | DeviceState={1} | {2}" -f $guid, $st, (Get-FriendlyName $guid))
    }
    Write-Host ""
    Write-Host "Informe -Id com o GUID do endpoint que quer habilitar (use os de DeviceState=2)."
    exit 0
}

# Normaliza "{0.0.1...}.{GUID}" -> "{GUID}"
if ($Id -match '\{0\.0\.[01]\.00000000\}\.\{([0-9a-fA-F\-]+)\}') { $Id = "{$($Matches[1])}" }
if ($Id -notmatch '^\{[0-9a-fA-F\-]+\}$') { Write-Host "ERRO: Id invalido: $Id"; exit 1 }

$key = Join-Path $base $Id
if (-not (Test-Path $key)) { Write-Host "ERRO: endpoint nao encontrado: $Id"; exit 1 }

$old = (Get-ItemProperty $key -Name DeviceState -ErrorAction SilentlyContinue).DeviceState
Set-ItemProperty -Path $key -Name DeviceState -Value 268435457 -Type DWord
$new = (Get-ItemProperty $key -Name DeviceState).DeviceState

Write-Host ("{0}: DeviceState {1} -> {2}" -f (Get-FriendlyName $Id), $old, $new)

Write-Host "Reiniciando AudioEndpointBuilder..."
Restart-Service -Name AudioEndpointBuilder -Force
Start-Sleep -Seconds 4
Write-Host ("AudioEndpointBuilder: {0}" -f (Get-Service AudioEndpointBuilder).Status)
Write-Host "Pronto. Rode o audio-mic.ps1 novamente para confirmar (estado deve virar ATIVO)."
