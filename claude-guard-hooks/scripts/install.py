#!/usr/bin/env python3
"""Instala (ou remove) o guard.py como hook PreToolUse no settings.json do Claude Code.

Uso:
  python3 -I install.py [--dry-run] [--uninstall] [--settings CAMINHO]

Idempotente: reconhece a própria entrada pelo caminho do guard.py e não duplica.
Faz backup do settings.json antes de gravar (settings.json.bak-guard-AAAAMMDD-HHMMSS).
Preserva todas as outras chaves e hooks existentes.
"""
import argparse
import datetime
import json
import os
import shutil
import sys

MARKER = "claude-guard-hooks/scripts/guard.py"
COMMAND = 'python3 -I "$HOME/.claude/skills/claude-guard-hooks/scripts/guard.py"'
ENTRY = {
    "matcher": "Bash|Write|Edit|MultiEdit",
    "hooks": [{"type": "command", "command": COMMAND, "timeout": 10}],
}


def is_ours_hook(h):
    return isinstance(h, dict) and MARKER in str(h.get("command", ""))


def without_ours(groups):
    """Remove só as entradas do guard; mantém outros hooks do mesmo grupo de matcher."""
    out = []
    for g in groups:
        if not isinstance(g, dict):
            out.append(g)
            continue
        hooks = g.get("hooks", [])
        kept = [h for h in hooks if not is_ours_hook(h)]
        if len(kept) == len(hooks):
            out.append(g)
        elif kept:
            out.append({**g, "hooks": kept})
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--settings", default=os.path.expanduser("~/.claude/settings.json"))
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--uninstall", action="store_true")
    args = ap.parse_args()

    target = os.path.expanduser("~/.claude/skills/claude-guard-hooks/scripts/guard.py")
    if not args.uninstall and not os.path.exists(target):
        print(f"ERRO: {target} não existe. Rode antes o sync das skills (bin/sync-skills.sh claude).", file=sys.stderr)
        return 1

    data = {}
    if os.path.exists(args.settings):
        with open(args.settings, encoding="utf-8") as f:
            data = json.load(f)
    hooks = data.setdefault("hooks", {})
    pre = hooks.setdefault("PreToolUse", [])
    kept = without_ours(pre)
    had_ours = kept != pre
    if args.uninstall:
        new_pre = kept
        action = "remover" if had_ours else "nada a remover"
    else:
        new_pre = kept + [ENTRY]
        action = "atualizar" if had_ours else "adicionar"
    if new_pre:
        hooks["PreToolUse"] = new_pre
    else:
        hooks.pop("PreToolUse", None)
    if not hooks:
        data.pop("hooks", None)

    print(f"{action}: hook guard em {args.settings}")
    if args.dry_run:
        print(json.dumps(data.get("hooks", {}), indent=2, ensure_ascii=False))
        return 0
    # Grava no arquivo real: se settings.json for symlink (dotfiles), o link continua link.
    real = os.path.realpath(args.settings)
    mode = 0o600
    if os.path.exists(real):
        stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        shutil.copy2(real, f"{args.settings}.bak-guard-{stamp}")
        mode = os.stat(real).st_mode & 0o777
    tmp = real + ".tmp-guard"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.chmod(tmp, mode)
    os.replace(tmp, real)
    print("ok. Vale a partir da próxima sessão do Claude Code (ou depois de /hooks recarregar).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
