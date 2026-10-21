---
name: windows-audio-mic
description: Diagnostica e corrige microfone que não capta som no Windows — padrão mudo (mute), volume zerado, dispositivo padrão errado (ex. "Mixagem estéreo"/loopback em Comunicações) e endpoint desabilitado. Use quando o usuário relatar "microfone não funciona", "não está reconhecendo/captando som", app de voz sem áudio de entrada (Teams/Zoom/Discord/Meet/OBS), ou pedir para verificar/ajustar a entrada de áudio do Windows.
---

# Skill: windows-audio-mic

**Tipo:** internal

## Quando executar

- "o microfone não está funcionando" / "não tá reconhecendo som" / "não capta áudio"
- App de voz (Teams, Zoom, Discord, Meet, OBS) sem entrada de áudio
- Suspeita de mudo, volume zerado ou dispositivo padrão incorreto
- Pedido para verificar/ajustar a entrada de áudio do Windows

## Regra de ouro (não errar o diagnóstico)

- **Não** diagnosticar pelo registro `HKLM\...\MMDevices\Audio\Capture\*\DeviceState`. Ele só diz
  ativo/desabilitado e é fácil ler ao contrário: `1 = ATIVO`, `2 = DESABILITADO`, `4 = NÃO PRESENTE`,
  `8 = DESCONECTADO`; o bit `0x10000000` marca o dispositivo padrão. Mudo e volume **não** ficam lá.
- **Mudo e volume** só existem na API Core Audio (`IAudioEndpointVolume::GetMute` /
  `GetMasterVolumeLevelScalar`). É o sintoma mais comum: volume 100% **com mudo ligado**.
- O dispositivo padrão tem 3 papéis: Console (`eConsole`), Multimídia (`eMultimedia`) e
  **Comunicações** (`eCommunications`). Apps de voz usam **Comunicações** — se estiver em
  "Mixagem estéreo"/loopback, não capta voz mesmo com o mic bom.

## Diagnóstico (somente leitura)

```powershell
powershell -ExecutionPolicy Bypass -File scripts/audio-mic.ps1
```

Lista, por endpoint de captura: nome, estado real, volume e **mudo**; e o dispositivo padrão por papel.

## Corrigir (sem admin)

```powershell
powershell -ExecutionPolicy Bypass -File scripts/audio-mic.ps1 -Fix
```

- Desmuta todos os microfones ativos e põe volume em 100%.
- Define o microfone interno como padrão nos 3 papéis via `IPolicyConfig::SetDefaultEndpoint`.
- Use `-SetDefaultId "{0.0.1.00000000}.{GUID}"` para escolher outro endpoint (ex. mic do headset).

## Casos, causa e o que exige admin

| Sintoma | Causa | Ação | Admin? |
|---|---|---|---|
| Mic padrão com `mudo=True` | mute no endpoint | `-Fix` | não |
| Comunicações = "Mixagem estéreo" | app de voz pega loopback | `-Fix` | não |
| Volume 0% | volume do endpoint | `-Fix` | não |
| Estado `2` (DESABILITADO) | desabilitado em Som → Gravação | `scripts/enable-endpoint.ps1` (admin) | **sim** |
| Estado `4`/`8` | dispositivo não plugado | conectar o microfone | — |

## Habilitar endpoint desabilitado (exige admin)

```powershell
powershell -ExecutionPolicy Bypass -File scripts/enable-endpoint.ps1 -Id "{65226944-...}"
```

Grava `DeviceState=268435457` em `HKLM\...\MMDevices\Audio\Capture\{Id}` e reinicia o
`AudioEndpointBuilder`. Só funciona em sessão elevada (UAC). Alternativa sem script: Som → aba
Gravação → "Mostrar dispositivos desabilitados" → botão direito → Habilitar.

## Observações

- Mudo/volume/padrão são por endpoint **e por usuário** → `-Fix` não precisa de admin.
- **Reiniciar o app de voz** depois, para ele reler o dispositivo padrão.
- Nomes típicos: interno = "Grupo de microfones"; headset P2 = "Microfone Externo"; USB =
  "Microfone (USB Audio Device)".
- Se o mic voltar a mutar, checar mute físico (tecla F4/botão do headset).
