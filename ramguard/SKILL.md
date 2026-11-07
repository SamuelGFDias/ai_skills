---
name: ramguard
description: Opera e ajusta o ramguard (servico que encerra o processo mais pesado quando a RAM fica alta) e a lista de processos que nunca podem ser encerrados. Use quando um jogo ou app foi fechado "do nada" por falta de RAM, quando aparecer a notificacao "RAM em N%: encerrei ...", ou ao proteger processos, ajustar limiares ou depurar o ramguard.
metadata:
  type: reference
---

**Tipo:** internal

# ramguard

Servico systemd (`/etc/systemd/system/ramguard.service`) que roda `/usr/local/sbin/ramguard --tiers 90:20,95:10,98:2`: se o uso de RAM ficar acima de PCT por SEGUNDOS, envia SIGTERM (SIGKILL apos 5s) ao processo com maior `oom_score` e avisa via `notify-send`. Fonte versionada no repo `SO` (`~/SO/system/...`).

## Processos que nunca sao encerrados

1. **Jogos da Steam (automatico):** qualquer processo cujo ambiente (`/proc/PID/environ`) tenha `SteamAppId` ou `SteamGameId`, nativo ou Proton. Nao precisa listar por nome: o `comm` do jogo varia (ex.: `Unity Main Thre` e nome de thread, nao do executavel).
2. **`/etc/ramguard/never-kill.list`:** um nome de `comm` por linha (max 15 chars) ou `@grupo`; `#` comenta. Lida a cada escolha de alvo, **sem reiniciar** o servico.
3. **`PROTECTED` no script:** sistema/desktop (gnome-shell, systemd, sshd, ...), fixo no codigo.
4. **Claude Code:** o `comm` `claude` esta no grupo `@dev-tools` (`groups/dev-tools.txt`), que ja vem em `never-kill.list`. Encerrar o Claude perderia a sessao de trabalho.

Avisos (sem matar nada): com a RAM em `AVISO_PCT`=93% ou mais e o ramguard sem poder agir (pausado por jogo/pause-while, ou sem alvo valido) sai `RAM 94%: ramguard sem poder agir (pausado: ...) — maiores protegidos: ...`. Em 97% (`CRITICO_PCT`) o texto vem com `CRITICO`. Um protegido sozinho acima de 25% da RAM gera `<nome> usa N% da RAM e esta protegido`. No maximo 1 aviso por nivel (e por processo, no caso de 25%) a cada 60s; o limite zera quando a RAM cai abaixo de 91%. Constantes no topo do script.

## Grupos (`@nome`)

Uma linha `@nome` numa lista inclui `/etc/ramguard/groups/nome.txt` (um `comm` por linha, `#` comenta; grupos podem incluir grupos). Sem reiniciar. Fonte: `~/SO/system/etc/ramguard/groups/`.

| Grupo | Conteudo |
|---|---|
| `plasma-core` | sessao/desktop Plasma (plasmashell, kwin, kded6, polkit, portais xdg, plasma-keyboard...) |
| `system-core` | keyd, pipewire, wireplumber, rede, bluetooth, energia, nvidia-powerd, 1password |
| `steam-core` | steam, steamwebhelper, reaper, pressure-vessel (cliente, nao os jogos) |
| `steam-games` | jogos que o usuario vai preenchendo (fora da Steam ou que escapem da deteccao) |
| `dev-tools` | `claude` (Claude Code): nunca encerrado |

`never-kill.list` usa os cinco. Para proteger um jogo: ache o nome com `ps -eo comm | grep -i NOME` e acrescente em `groups/steam-games.txt`.

## Pausa durante o jogo

O ramguard **nao encerra nada** enquanto houver um jogo da Steam rodando (detectado por `SteamAppId`/`SteamGameId`; so a Steam aberta nao pausa) ou um processo de `/etc/ramguard/pause-while.list` (aceita nomes e `@grupo`; padrao `@steam-games`). Log: `ramguard pausado`.

A cada 5s ele tambem grava `oom_score_adj=-900` nos jogos (Steam por ambiente + `@steam-games`), para o earlyoom e o kernel os pouparem. Nao usa -1000 de proposito.

Aviso de protegido grande (>25% da RAM): repete no maximo a cada 10 min e zera quando o processo cai para <=25%. Erro persistente no loop loga o traceback no maximo 1x por minuto por tipo de excecao, com "(+N iguais)" no log seguinte.

Hardening do servico (`systemd-analyze security`: 9.6 -> 6.0): NoNewPrivileges, ProtectSystem=strict, PrivateTmp, ProtectKernel/Control/Clock, RestrictAddressFamilies=AF_UNIX AF_NETLINK, e CapabilityBoundingSet restrito a KILL, IPC_LOCK, SYS_RESOURCE, SYS_PTRACE, DAC_OVERRIDE, SETUID, SETGID, AUDIT_WRITE (cada uma provada em `systemd-run`). NAO adicionar ProtectHome=yes (esconde /run/user e o notify-send falha), nem ProtectProc/ProcSubset/PrivateUsers/SystemCallFilter. Ao mexer em capability, teste antes com `systemd-run --wait --pipe -p ...`.

## Diagnostico

```bash
journalctl -u ramguard -n 20 --no-pager          # "RAM X% > Y% por Zs -> alvo: (score, pid, comm, MiB)"
systemctl show ramguard -p ActiveEnterTimestamp  # desde quando roda; compare com o horario do kill
grep -c is_steam_game /usr/local/sbin/ramguard   # >=1 = versao com protecao da Steam instalada
```

Armadilha: se o jogo foi encerrado mesmo apos o ajuste, confira primeiro se o servico foi **reiniciado** com o script novo (o processo em memoria continua o codigo antigo ate `systemctl restart ramguard`).

Cooldown: o mesmo `comm` nao e encerrado de novo em 60s se a RAM nao caiu 1 ponto desde o ultimo kill; o ramguard passa ao proximo candidato (sem outro, so loga). Aviso no maximo 1 vez por `comm` a cada 60s. Log do kill: `kill comm=.. pid=.. score=.. adj=.. rss_mib=.. used_antes=..% used_depois=..% sinal=SIGTERM|SIGKILL`. O kill usa pidfd (sem risco de PID reciclado); `mlockall` usa MCL_ONFAULT (kernel antigo cai para o modo antigo).
Testes sem root: `python3 -I -m unittest discover -s ~/SO/tests -v` (arquivo `~/SO/tests/test_ramguard.py`).

## Testar sem matar nada

```bash
python3 -I /usr/local/sbin/ramguard --tiers 1:1 --dry-run   # Ctrl+C; mostra o alvo escolhido, nao envia sinal
```

Com um jogo aberto o ramguard fica pausado; sem jogo, o alvo nao pode ser nada de `never-kill` (nem o `steamwebhelper`). Como usuario comum o `mlockall` falha (aviso inofensivo) e so se enxergam processos proprios.

## Limite

Proteger o jogo nao cria RAM: com jogo aberto o ramguard pausa e, se a RAM chegar perto de 100%, quem age e o kernel/earlyoom (que prefere abas do Firefox) ou o sistema trava. Opcoes: ajustar `--tiers`, reduzir o consumo do jogo, ou aumentar swap/zram.

## Instalar alteracoes

Edite em `~/SO` e rode `./install.sh` (idempotente, faz backup `*.bak.<timestamp>` e reinicia o servico).
