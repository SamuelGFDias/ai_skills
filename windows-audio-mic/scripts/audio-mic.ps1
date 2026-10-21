<#
.SYNOPSIS
  Diagnostica e corrige captura de microfone no Windows (mudo, volume, dispositivo padrão).

.DESCRIPTION
  Lê o estado AO VIVO dos endpoints de captura via Core Audio API
  (IMMDeviceEnumerator / IMMDevice / IAudioEndpointVolume) e, com -Fix, desmuta, ajusta o volume
  para 100% e define o microfone como padrão em todos os papéis (IPolicyConfig::SetDefaultEndpoint).
  NÃO requer admin. O registro HKLM\...\MMDevices\...\DeviceState NÃO informa mudo/volume — não usar
  para diagnosticar (ver SKILL.md).

.PARAMETER Fix
  Aplica as correções: desmuta, volume 100% e define o padrão.

.PARAMETER SetDefaultId
  Endpoint a definir como padrão, no formato {0.0.1.00000000}.{GUID}.
  Padrão: "Grupo de microfones" (mic interno); senão o primeiro mic real ativo.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File audio-mic.ps1
  powershell -ExecutionPolicy Bypass -File audio-mic.ps1 -Fix
  powershell -ExecutionPolicy Bypass -File audio-mic.ps1 -Fix -SetDefaultId "{0.0.1.00000000}.{d7f1fc99-...}"
#>
[CmdletBinding()]
param(
    [switch]$Fix,
    [string]$SetDefaultId
)

$ErrorActionPreference = 'Stop'

# ---------- Interop Core Audio ----------
$code = @'
using System;
using System.Runtime.InteropServices;

[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
public class MMDeviceEnumeratorComObject { }

[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceEnumerator {
    int EnumAudioEndpoints(int dataFlow, int dwStateMask, out IMMDeviceCollection ppDevices);
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppEndpoint);
    int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string pwstrId, out IMMDevice ppDevice);
    int RegisterEndpointNotificationCallback(IntPtr pClient);
    int UnregisterEndpointNotificationCallback(IntPtr pClient);
}

[Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceCollection {
    int GetCount(out int pcDevices);
    int Item(int nDevice, out IMMDevice ppDevice);
}

[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDevice {
    int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, out IntPtr ppInterface);
    int OpenPropertyStore(int stgmAccess, out IntPtr ppProperties);
    int GetId([MarshalAs(UnmanagedType.LPWStr)] out string ppstrId);
    int GetState(out int pdwState);
}

[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioEndpointVolume {
    int RegisterControlChangeNotify(IntPtr pNotify);
    int UnregisterControlChangeNotify(IntPtr pNotify);
    int GetChannelCount(out int pnChannelCount);
    int SetMasterVolumeLevel(float fLevelDB, IntPtr pguidEventContext);
    int SetMasterVolumeLevelScalar(float fLevel, IntPtr pguidEventContext);
    int GetMasterVolumeLevel(out float pfLevelDB);
    int GetMasterVolumeLevelScalar(out float pfLevel);
    int SetChannelVolumeLevel(int nChannel, float fLevelDB, IntPtr pguidEventContext);
    int SetChannelVolumeLevelScalar(int nChannel, float fLevel, IntPtr pguidEventContext);
    int GetChannelVolumeLevel(int nChannel, out float pfLevelDB);
    int GetChannelVolumeLevelScalar(int nChannel, out float pfLevel);
    int SetMute(bool bMute, IntPtr pguidEventContext);
    int GetMute(out bool pbMute);
    int GetVolumeStepInfo(out int pnStep, out int pnStepCount);
    int VolumeStepUp(IntPtr pguidEventContext);
    int VolumeStepDown(IntPtr pguidEventContext);
    int QueryHardwareSupport(out int pdwHardwareSupportMask);
    int GetVolumeRange(out float pfMin, out float pfMax, out float pfIncrement);
}

[Guid("F8679F50-850A-41CF-9C72-430F290290C8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IPolicyConfig {
    int GetMixFormat([MarshalAs(UnmanagedType.LPWStr)] string pszDeviceName, IntPtr ppFormat);
    int GetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string pszDeviceName, [MarshalAs(UnmanagedType.Bool)] bool bDefault, IntPtr ppFormat);
    int ResetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string pszDeviceName);
    int SetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string pszDeviceName, IntPtr pEndpointFormat, IntPtr MixFormat);
    int GetProcessingPeriod([MarshalAs(UnmanagedType.LPWStr)] string pszDeviceName, [MarshalAs(UnmanagedType.Bool)] bool bDefault, IntPtr pmftDefaultPeriod, IntPtr pmftMinimumPeriod);
    int SetProcessingPeriod([MarshalAs(UnmanagedType.LPWStr)] string pszDeviceName, IntPtr pmftPeriod);
    int GetShareMode([MarshalAs(UnmanagedType.LPWStr)] string pszDeviceName, IntPtr pMode);
    int SetShareMode([MarshalAs(UnmanagedType.LPWStr)] string pszDeviceName, IntPtr mode);
    int GetPropertyValue([MarshalAs(UnmanagedType.LPWStr)] string pszDeviceName, [MarshalAs(UnmanagedType.Bool)] bool bFxStore, IntPtr key, IntPtr pv);
    int SetPropertyValue([MarshalAs(UnmanagedType.LPWStr)] string pszDeviceName, [MarshalAs(UnmanagedType.Bool)] bool bFxStore, IntPtr key, IntPtr pv);
    int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string pszDeviceName, int role);
    int SetEndpointVisibility([MarshalAs(UnmanagedType.LPWStr)] string pszDeviceName, [MarshalAs(UnmanagedType.Bool)] bool bVisible);
}

public class EndpointInfo {
    public string Id;
    public int State;
    public bool Mute;
    public float Volume;
}

public static class AudioMic {
    public static EndpointInfo[] CaptureAll() {
        var en = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
        IMMDeviceCollection col;
        en.EnumAudioEndpoints(1, 0xF, out col); // eCapture, DEVICE_STATEMASK_ALL
        int count; col.GetCount(out count);
        var list = new System.Collections.Generic.List<EndpointInfo>();
        for (int i = 0; i < count; i++) {
            IMMDevice dev; col.Item(i, out dev);
            var info = new EndpointInfo();
            dev.GetId(out info.Id);
            dev.GetState(out info.State);
            info.Volume = -1f; info.Mute = false;
            if (info.State == 1) {
                try {
                    Guid iid = typeof(IAudioEndpointVolume).GUID;
                    IntPtr pv;
                    dev.Activate(ref iid, 23, IntPtr.Zero, out pv); // CLSCTX_ALL
                    var v = (IAudioEndpointVolume)Marshal.GetObjectForIUnknown(pv);
                    v.GetMasterVolumeLevelScalar(out info.Volume);
                    v.GetMute(out info.Mute);
                } catch { }
            }
            list.Add(info);
        }
        return list.ToArray();
    }

    public static string Default(int role) {
        var en = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
        IMMDevice dev;
        int hr = en.GetDefaultAudioEndpoint(1, role, out dev);
        if (hr != 0) return null;
        string id; dev.GetId(out id);
        return id;
    }

    public static string Unmute(string id, float level) {
        var en = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
        IMMDevice dev;
        int hr = en.GetDevice(id, out dev);
        if (hr != 0) return "GetDevice hr=" + hr;
        Guid iid = typeof(IAudioEndpointVolume).GUID;
        IntPtr pv;
        hr = dev.Activate(ref iid, 23, IntPtr.Zero, out pv);
        if (hr != 0) return "Activate hr=" + hr;
        var v = (IAudioEndpointVolume)Marshal.GetObjectForIUnknown(pv);
        v.SetMute(false, IntPtr.Zero);
        v.SetMasterVolumeLevelScalar(level, IntPtr.Zero);
        bool m; v.GetMute(out m);
        float lv; v.GetMasterVolumeLevelScalar(out lv);
        return "mudo=" + m + " vol=" + (lv * 100).ToString("N0") + "%";
    }

    public static string SetDefault(string id, int role) {
        Type t = Type.GetTypeFromCLSID(new Guid("870AF99C-171D-4F9E-AF0D-E63DF40C2BC9"));
        IPolicyConfig pc = (IPolicyConfig)Activator.CreateInstance(t);
        return "hr=" + pc.SetDefaultEndpoint(id, role);
    }
}
'@

if (-not ('AudioMic' -as [type])) {
    Add-Type -TypeDefinition $code -ErrorAction Stop
}

# ---------- Helpers ----------
$base = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Capture"
$pName = '{a45c254e-df1c-4efd-8020-67d146a850e0},2'
$pDev  = '{b3f8fa53-0004-438e-9003-51a46e139bfc},6'

function Get-FriendlyName([string]$id) {
    $guid = ($id -replace '.*\.', '')
    $pp = Join-Path $base "$guid\Properties"
    $o1 = Get-ItemProperty -Path $pp -Name $pName -ErrorAction SilentlyContinue
    $o2 = Get-ItemProperty -Path $pp -Name $pDev  -ErrorAction SilentlyContinue
    $n1 = if ($o1) { $o1.$pName } else { '?' }
    $n2 = if ($o2) { $o2.$pDev } else { '?' }
    "{0} ({1})" -f $n1, $n2
}

$stateLabel = @{ 1 = 'ATIVO'; 2 = 'DESABILITADO'; 4 = 'NAO_PRESENTE'; 8 = 'DESCONECTADO' }

# ---------- Diagnostico ----------
$endpoints = [AudioMic]::CaptureAll()

Write-Host "=== ENDPOINTS DE CAPTURA ==="
foreach ($e in $endpoints) {
    $vn = if ($e.Volume -lt 0) { 'n/a' } else { "{0:N0}%" -f ($e.Volume * 100) }
    $lbl = $stateLabel[[int]$e.State]; if (-not $lbl) { $lbl = "ESTADO($($e.State))" }
    Write-Host ("  {0}" -f (Get-FriendlyName $e.Id))
    Write-Host ("     {0} | vol={1} | mudo={2}" -f $lbl, $vn, $e.Mute)
    Write-Host ("     {0}" -f $e.Id)
}

Write-Host ""
Write-Host "=== DISPOSITIVO DE CAPTURA PADRAO ==="
$roles = @{ 0 = 'Console'; 1 = 'Multimidia'; 2 = 'Comunicacoes' }
foreach ($r in 0, 1, 2) {
    $d = [AudioMic]::Default($r)
    if ($d) {
        Write-Host ("  {0}: {1}" -f $roles[$r], (Get-FriendlyName $d))
    } else {
        Write-Host ("  {0}: (nenhum)" -f $roles[$r])
    }
}

# ---------- Correcao ----------
if ($Fix) {
    Write-Host ""
    Write-Host "=== APLICANDO CORRECOES ==="
    $lvl = [single]1.0

    $active = @($endpoints | Where-Object { $_.State -eq 1 })
    foreach ($e in $active) {
        Write-Host ("  desmutando {0} -> {1}" -f (Get-FriendlyName $e.Id), [AudioMic]::Unmute($e.Id, $lvl))
    }

    $target = $SetDefaultId
    if (-not $target) {
        $pref = $active | Where-Object { (Get-FriendlyName $_.Id) -like 'Grupo de microfones*' } | Select-Object -First 1
        if (-not $pref) { $pref = $active | Select-Object -First 1 }
        if ($pref) { $target = $pref.Id }
    }
    if ($target) {
        foreach ($r in 0, 1, 2) {
            Write-Host ("  padrao role={0} -> {1} ({2})" -f $r, (Get-FriendlyName $target), [AudioMic]::SetDefault($target, $r))
        }
        Write-Host ""
        Write-Host "Pronto. REINICIE o app de voz para ele reler o dispositivo padrao."
    } else {
        Write-Host "  AVISO: nenhum endpoint ativo para definir como padrao."
    }

    $disabled = @($endpoints | Where-Object { $_.State -eq 2 })
    if ($disabled.Count -gt 0) {
        Write-Host ""
        Write-Host "ATENCAO: ha endpoint DESABILITADO (estado 2). Habilitar exige admin:"
        Write-Host "  powershell -ExecutionPolicy Bypass -File scripts/enable-endpoint.ps1 -Id '{GUID}'"
    }
}
