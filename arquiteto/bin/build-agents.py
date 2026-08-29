#!/usr/bin/env python3
"""Gera os agentes do arquiteto em arquiteto/dist/<cli>/ a partir da fonte canônica.

Fonte canônica: arquiteto/roles/<papel>.md (frontmatter name/description/effort/color/readonly + corpo).
Mapeamento por CLI: arquiteto/cli/<cli>/models.json (papel -> {model, ...}).

Os agentes gerados são COMMITADOS em dist/<cli>/ (configuração já validada por CLI).
A instalação no diretório real de cada CLI é feita por bin/sync-agents.sh via symlink,
então um git pull propaga mudanças sem rodar este gerador.

Uso:
  build-agents.py <cli>                # grava em arquiteto/dist/<cli>/
  build-agents.py --check              # verifica se dist está em dia com roles+models (drift)
  build-agents.py --list               # lista CLIs suportados
  build-agents.py <cli> --target <dir> # destino alternativo (uso pontual)
"""
import json
import sys
import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent  # arquiteto/
ROLES_DIR = ROOT / "roles"
CLI_DIR = ROOT / "cli"
DIST_DIR = ROOT / "dist"

READONLY_TOOLS = "Edit, Write, NotebookEdit, Agent"


def parse_role(path: Path):
    """Lê roles/<nome>.md: frontmatter yaml + corpo."""
    text = path.read_text(encoding="utf-8")
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
    if not m:
        raise ValueError(f"frontmatter ausente em {path}")
    meta = {}
    for line in m.group(1).splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            meta[k.strip()] = v.strip()
    body = m.group(2).strip()
    return meta, body


def build_claude(meta, body, cfg):
    dt = cfg.get("disallowedTools", ["Agent"])
    if isinstance(dt, list):
        dt = ", ".join(dt)
    header = (
        "---\n"
        f"name: {meta['name']}\n"
        f"description: {meta['description']}\n"
        f"model: {cfg['model']}\n"
        f"effort: {cfg.get('effort', meta.get('effort', 'medium'))}\n"
        f"disallowedTools: {dt}\n"
        f"color: {meta.get('color', 'blue')}\n"
        "---\n\n"
    )
    return header + body + "\n"


def build_kilo(meta, body, cfg):
    perm_lines = ["  task: deny"]
    if meta.get("readonly") == "true":
        perm_lines.append("  edit: deny")
    header = (
        "---\n"
        f"name: {meta['name']}\n"
        f"description: {meta['description']}\n"
        f"mode: subagent\n"
        f"model: {cfg['model']}\n"
        "permission:\n" + "\n".join(perm_lines) + "\n"
        "---\n\n"
    )
    return header + body + "\n"


def build_codex(meta, body, cfg):
    sandbox = cfg.get("sandbox", "read-only" if meta.get("readonly") == "true" else "workspace-write")
    reasoning = cfg.get("reasoning", "medium")
    toml = (
        f'name = "{meta["name"]}"\n'
        f'description = "{meta["description"]}"\n'
        f'model = "{cfg["model"]}"\n'
        f'model_reasoning_effort = "{reasoning}"\n'
        f'sandbox_mode = "{sandbox}"\n'
        f'developer_instructions = """\n{body}\n"""\n'
    )
    return toml


BUILDERS = {"claude": build_claude, "kilo": build_kilo, "codex": build_codex}
EXT = {"claude": ".md", "kilo": ".md", "codex": ".toml"}


def build_cli(cli):
    """Retorna {nome_arquivo: conteudo} para um CLI."""
    models = json.loads((CLI_DIR / cli / "models.json").read_text(encoding="utf-8"))
    out = {}
    for role_path in sorted(ROLES_DIR.glob("*.md")):
        meta, body = parse_role(role_path)
        cfg = models[meta["name"]]
        out[f"{meta['name']}{EXT[cli]}"] = BUILDERS[cli](meta, body, cfg)
    return out


def check_drift(cli):
    """Verifica se dist/<cli> está em dia com roles/ + cli/<cli>/models.json. Retorna 0 se ok, 2 se drift."""
    generated = build_cli(cli)
    target = DIST_DIR / cli
    stale = [f for f in target.glob(f"*{EXT[cli]}") if f.name not in generated]
    drift = []
    for name, content in generated.items():
        path = target / name
        if not path.exists():
            drift.append(f"  FALTA: {name}")
        elif path.read_text(encoding="utf-8") != content:
            drift.append(f"  DIVERGE: {name}")
    if stale:
        drift.append("  ÓRFÃOS (não gerados mais): " + ", ".join(f.name for f in stale))
    if drift:
        print(f"DRIFT em {target}:")
        print("\n".join(drift))
        print("Rode 'python3 build-agents.py' e commite dist/.")
        return 2
    print(f"OK: dist/{cli} em dia com roles/ + cli/{cli}/models.json")
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cli", nargs="?", help="claude | kilo | codex")
    ap.add_argument("--target", help="destino alternativo (default: arquiteto/dist/<cli>)")
    ap.add_argument("--list", action="store_true", help="mostra CLIs suportados")
    ap.add_argument("--check", action="store_true", help="verifica drift entre roles+models e dist/")
    args = ap.parse_args()

    if args.check:
        clis = [args.cli] if args.cli else sorted(BUILDERS)
        rc = 0
        for c in clis:
            r = check_drift(c)
            if r:
                rc = 2
        return rc

    if args.list or not args.cli:
        print("CLIs suportados:", ", ".join(sorted(BUILDERS)))
        return 0

    cli = args.cli
    if cli not in BUILDERS:
        print(f"CLI desconhecido: {cli}", file=sys.stderr)
        return 1

    generated = build_cli(cli)
    target = Path(args.target) if args.target else DIST_DIR / cli
    target.mkdir(parents=True, exist_ok=True)
    for name, content in generated.items():
        (target / name).write_text(content, encoding="utf-8")
        print(f"  {target / name}  ({name})")
    print(f"\nGerados {len(generated)} agentes em {target} — commite dist/.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
