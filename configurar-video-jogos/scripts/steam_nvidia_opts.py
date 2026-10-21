#!/usr/bin/env python3
"""Adiciona as opcoes de inicializacao da NVIDIA (PRIME offload) aos jogos da Steam.

Uso:
  steam_nvidia_opts.py [--dry-run] [appid ...]

Sem appids: aplica em todos os jogos instalados (ignora runtimes e ferramentas).
Com --dry-run: so mostra o que mudaria, sem gravar nada.

A Steam precisa estar fechada: ela reescreve o localconfig.vdf ao sair e
sobrescreveria a mudanca. Cada arquivo alterado recebe um backup
*.bak-nvidia-<timestamp> ao lado.
"""
import glob
import os
import re
import shutil
import subprocess
import sys
import time

OPTS = "__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only %command%"
SKIP_NAMES = re.compile(r"Steam Linux Runtime|Proton|Steamworks", re.I)
STEAM_ROOTS = [
    os.path.expanduser("~/.var/app/com.valvesoftware.Steam/.local/share/Steam"),
    os.path.expanduser("~/.local/share/Steam"),
    os.path.expanduser("~/.steam/steam"),
]


def steam_root():
    for root in STEAM_ROOTS:
        if os.path.isdir(os.path.join(root, "steamapps")):
            return root
    sys.exit("Steam nao encontrada em nenhum dos caminhos conhecidos.")


def steam_running():
    return subprocess.run(
        ["pgrep", "-f", "steamwebhelper|ubuntu12_32/steam|-- steam"],
        capture_output=True,
    ).returncode == 0


def installed_games(root):
    games = {}
    for manifest in glob.glob(os.path.join(root, "steamapps", "appmanifest_*.acf")):
        text = open(manifest, encoding="utf-8").read()
        appid = re.search(r'"appid"\s+"(\d+)"', text)
        name = re.search(r'"name"\s+"([^"]+)"', text)
        if appid and name:
            games[appid.group(1)] = name.group(1)
    return games


def find_block_end(lines, open_idx):
    depth = 0
    for k in range(open_idx, len(lines)):
        s = lines[k].strip()
        if s == "{":
            depth += 1
        elif s == "}":
            depth -= 1
            if depth == 0:
                return k
    sys.exit("bloco sem fechamento no localconfig.vdf")


def plan_edits(lines, appids):
    """Devolve (edicoes, appids_tratados). Cada edicao: (indice, 'insert'|'replace', texto)."""
    apps_open = next(
        (i + 1 for i, s in enumerate(lines[:-1])
         if s.strip() == '"apps"' and lines[i + 1].strip() == "{"),
        None,
    )
    if apps_open is None:
        sys.exit("secao \"apps\" nao encontrada")
    apps_end = find_block_end(lines, apps_open)

    edits, handled = [], set()
    j = apps_open + 1
    while j < apps_end:
        s = lines[j].strip()
        is_key = s.startswith('"') and s.endswith('"') and j + 1 < apps_end
        if is_key and lines[j + 1].strip() == "{":
            end = find_block_end(lines, j + 1)
            appid = s[1:-1]
            if appid in appids:
                handled.add(appid)
                brace = lines[j + 1]
                indent = brace[: len(brace) - len(brace.lstrip())] + "\t"
                new = f'{indent}"LaunchOptions"\t\t"{OPTS}"'
                existing = [k for k in range(j + 2, end) if lines[k].strip().startswith('"LaunchOptions"')]
                if existing:
                    if lines[existing[0]].strip() != new.strip():
                        edits.append((existing[0], "replace", new))
                else:
                    edits.append((j + 1, "insert", new))
            j = end + 1
            continue
        j += 1
    return edits, handled


def apply_edits(lines, edits):
    out = list(lines)
    for idx, kind, text in sorted(edits, reverse=True):
        if kind == "replace":
            out[idx] = text
        else:
            out.insert(idx + 1, text)
    return out


def main():
    args = sys.argv[1:]
    dry = "--dry-run" in args
    requested = [a for a in args if not a.startswith("--")]

    root = steam_root()
    games = installed_games(root)
    if requested:
        appids = set(requested)
    else:
        appids = {a for a, n in games.items() if not SKIP_NAMES.search(n)}

    for appid in sorted(appids):
        print(f"  {appid}  {games.get(appid, '(nome desconhecido)')}")

    if steam_running() and not dry:
        sys.exit("A Steam esta aberta. Feche-a (Steam > Sair) e rode de novo.")

    configs = glob.glob(os.path.join(root, "userdata", "*", "config", "localconfig.vdf"))
    if not configs:
        sys.exit("nenhum localconfig.vdf encontrado (a Steam ja foi aberta nesta conta?)")

    for cfg in configs:
        lines = open(cfg, encoding="utf-8").read().split("\n")
        edits, handled = plan_edits(lines, appids)
        missing = appids - handled
        print(f"\n{cfg}")
        print(f"  alteracoes: {len(edits)}")
        for appid in sorted(missing):
            print(f"  aviso: {appid} nao esta no localconfig desta conta")
        if not edits or dry:
            continue
        stamp = time.strftime("%Y%m%d%H%M%S")
        shutil.copy2(cfg, f"{cfg}.bak-nvidia-{stamp}")
        with open(cfg, "w", encoding="utf-8") as fh:
            fh.write("\n".join(apply_edits(lines, edits)))
        print(f"  gravado (backup: {cfg}.bak-nvidia-{stamp})")


if __name__ == "__main__":
    main()
