---
name: configurar-video-jogos
description: Diagnostica e configura driver NVIDIA, GPU hibrida (Intel + NVIDIA PRIME) e jogos da Steam (Flatpak ou nativa) em Fedora. Use quando o usuario perguntar se a placa de video esta configurada, se um jogo usa a GPU certa, quando um jogo roda lento ou na Intel, ou ao mexer em driver, Vulkan, OpenGL, PRIME, Optimus ou opcoes de inicializacao da Steam.
metadata:
  type: reference
---

# Configurar video e jogos (NVIDIA hibrida + Steam)

Maquina de referencia: Fedora, Wayland, Intel UHD (GPU padrao) + NVIDIA RTX 4050 Max-Q, driver NVIDIA com modulos `nvidia`, `nvidia_drm`, `nvidia_modeset`, `nvidia_uvm`. Steam instalada como Flatpak `com.valvesoftware.Steam`.

## 1. Diagnostico (somente leitura)

Rode estes comandos e leia os resultados antes de mudar qualquer coisa:

```bash
lspci -k | grep -EA3 'VGA|3D|Display'        # qual driver esta em uso em cada GPU
nvidia-smi                                   # driver carregado, versao, uso de memoria
cat /proc/driver/nvidia/version              # versao exata do driver (usada na extensao Flatpak)
cat /sys/module/nvidia_drm/parameters/modeset  # deve ser Y
switcherooctl list                           # GPU padrao e variaveis para forcar a NVIDIA
flatpak list --runtime | grep -i nvidia      # extensao GL da NVIDIA dentro do Flatpak
flatpak override --show com.valvesoftware.Steam   # overrides; vazio = nenhum
```

Como saber se a Steam esta usando a NVIDIA: com um jogo aberto, `nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv`. O processo do jogo deve aparecer. Se so aparecer `kwin_wayland`, o jogo esta na Intel.

Quem controla a tela (importante para saber se "so NVIDIA" e possivel): `for c in /sys/class/drm/card*-*; do echo "$(basename $c): $(cat $c/status)"; done` mostra os conectores. Para descobrir qual card e qual GPU, use `readlink -f /sys/class/drm/cardN/device`. Se o `eDP-1` (painel interno) estiver `connected` numa GPU Intel e a NVIDIA nao tiver nenhum conector conectado, a NVIDIA nao conduz a tela: ela so renderiza e o frame e copiado para a Intel (PRIME offload). Nesse caso, "so NVIDIA" para a tela exige MUX de hardware na BIOS (ver secao 6).

## 2. Problema conhecido: Steam Flatpak sem driver NVIDIA

O Flatpak da Steam so enxerga o driver NVIDIA se houver a extensao `org.freedesktop.Platform.GL.nvidia-<versao>` (e `GL32` para jogos 32 bits) **com a mesma versao exata do driver do host**. Sem ela, o sandbox usa so o Mesa, e os jogos rodam na Intel.

Confirme no sandbox:

```bash
flatpak run --command=sh com.valvesoftware.Steam -c 'ls /usr/share/vulkan/icd.d/ | grep -i nvidia'
```

Vazio = sem driver NVIDIA no sandbox.

Correcao (substitua `615-78-08` pela versao de `/proc/driver/nvidia/version`, com pontos trocados por hifens):

```bash
flatpak remote-ls flathub --runtime | grep 'GL.*nvidia-615-78-08'   # confirme que existe
flatpak install -y flathub org.freedesktop.Platform.GL.nvidia-615-78-08 org.freedesktop.Platform.GL32.nvidia-615-78-08
```

Se a versao do driver nao existir no Flathub, use a Steam nativa (`sudo dnf install steam`, RPM Fusion), que usa o driver do host direto.

## 3. Opcoes de inicializacao por jogo

Para a GPU hibrida, cada jogo precisa de:

```
__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only %command%
```

Aplicar em todos os jogos instalados (ignora runtimes, Proton e Steamworks):

```bash
~/.claude/skills/configurar-video-jogos/scripts/steam_nvidia_opts.py --dry-run   # so mostra
~/.claude/skills/configurar-video-jogos/scripts/steam_nvidia_opts.py             # grava
~/.claude/skills/configurar-video-jogos/scripts/steam_nvidia_opts.py 570 105600  # so alguns appids
```

Regras do script:
- A Steam precisa estar **fechada**. Ela reescreve `localconfig.vdf` ao sair e apagaria a mudanca. O script recusa rodar com a Steam aberta.
- Cada `localconfig.vdf` alterado recebe backup `*.bak-nvidia-<timestamp>` ao lado.
- Idempotente: rodar de novo nao duplica nem altera nada se ja estiver certo.
- Edita so a secao `apps` principal. Esta indentacao importa: o arquivo tem outras secoes com appids iguais.

Para desfazer, restaure o backup (`cp <arquivo>.bak-nvidia-<timestamp> <arquivo>`) com a Steam fechada.

## 4. Testes

Teste pelo menos um jogo OpenGL e um Vulkan/Proton:

1. Abra a Steam (`flatpak run com.valvesoftware.Steam -silent`).
2. Inicie o jogo: `flatpak run com.valvesoftware.Steam steam://rungameid/<appid>`.
3. Confira na NVIDIA: `nvidia-smi pmon -c 1` ou `nvidia-smi --query-compute-apps=...`.
4. Para ver a espera sem `sleep` encadeado, use o Monitor com um loop `until`.

Exemplos validados nesta maquina: Terraria (105600, OpenGL) apareceu com ~1700 MiB; Age of Empires DE (1017900, Proton/Vulkan) apareceu como `AoEDE_s.exe` com ~870 MiB.

## 5. Armadilhas

- `vulkaninfo` nao existe no runtime da Steam Flatpak. Para testar Vulkan, use o jogo, nao o `vulkaninfo`.
- `steam://close/<appid>` nao fecha o jogo. Para encerrar tudo: `flatpak run com.valvesoftware.Steam -shutdown`.
- Ao filtrar `nvidia-smi` por "processo novo", exclua tambem o jogo que ja estava aberto, senao o filtro dispara falso positivo.
- A extensao Flatpak precisa bater com a versao do driver. Ao atualizar o driver, instale a extensao nova.
- Jogos nativos e Proton rodam no mesmo sandbox da Steam. Sem o passo 2, as opcoes de inicializacao nao tem efeito.
- Os backups `*.bak-nvidia-*` ficam em `~/.var/app/com.valvesoftware.Steam/.local/share/Steam/userdata/<id>/config/`. Apague-os quando nao precisar mais.
- Os arquivos de config dos jogos (ex.: `~/.var/app/com.valvesoftware.Steam/.local/share/Terraria/config.json`) sao reescritos pelo jogo ao sair. Editar com o jogo aberto perde a mudanca: feche o jogo antes, ou mude a opcao dentro do jogo.
- `prime-select`, `supergfxctl` e `envycontrol` nao estao instalados nesta maquina. Nao assuma que existem para trocar o modo da GPU.

## 6. Caso: travamento ao voltar para o jogo (tela cheia + PRIME + XWayland)

Sintoma: Terraria (105600) congela ao trocar de janela e voltar. Investigacao em 18/10/2026. Estado verificado:

- O jogo ja roda na NVIDIA: `nvidia-smi` mostrou `Terraria.bin.x86_64` com ~2600 MiB. As opcoes de inicializacao ja tinham `__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only`. Trocar para "so NVIDIA" nao mudaria a renderizacao do jogo.
- A tela e da Intel: `card1-eDP-1` (Intel) conectado; NVIDIA `Disp.A Off` e sem conector ativo. Sem MUX de hardware, a NVIDIA nao consegue conduzir o painel interno. Nao ha sinal de MUX no kernel (`acer_wmi` carregado, mas isso nao prova um MUX). Maquina: Acer Nitro ANV15-51, BIOS V1.53.
- Config do Terraria: `Fullscreen: true` + `WindowBorderless: true`. Ao sair do foco o jogo registrou `Resolucao alterada para: 1280x650`, ou seja, troca de modo de video no meio da sessao.
- Logs no mesmo periodo: o processo `gameoverlayui` da Steam foi iniciado e encerrado varias vezes nos 90 s antes de um crash nativo (SIGABRT) das 15:32 (`Main:EndDraw`, frame apresentado via overlay Vulkan). Nenhum log descreve diretamente o congelamento.
- Logs de crash: `coredumpctl info <pid>` (systemd-coredump). `client-crashlog.txt` na pasta do jogo so tinha registros antigos (16/10, erro de swapchain).

Conclusao: "so NVIDIA" para a tela nao e viavel sem MUX e nao era a correcao certa. Hipotese principal: tela cheia sem bordas com troca de modo de video e copia PRIME da NVIDIA para a Intel. Mudanca aplicada: `Fullscreen: false` no `config.json` do Terraria (jogo fechado antes).

Status: NAO VALIDADO. Para confirmar, jogar em janela, trocar de janela e voltar algumas vezes. Se congelar de novo, proximo teste: desligar a overlay da Steam so para o Terraria (propriedades do jogo na biblioteca). Se ainda assim congelar, investigar com `journalctl` no horario exato do congelamento.
