#!/usr/bin/env python3
"""Gera os agentes do arquiteto para um CLI específico a partir da fonte canônica.

Fonte canônica: arquiteto/roles/<papel>.md (frontmatter name/description/effort/color/readonly + corpo).
Mapeamento por CLI: arquiteto/cli/<cli>/models.json (papel -> {model, ...}).

Uso:
  build-agents.py <cli> [--target <dir>]   # cli: claude | kilo | codex
  build-agents.py --list                   # lista CLIs e destinos padrão
"""
import json
import os
import sys
import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent  # arquiteto/
ROLES_DIR = ROOT / "roles"
CLI_DIR = ROOT / "cli"

DEFAULT_TARGETS = {
    "claude": Path(os.environ["HOME"]) / ".claude" / "agents",
    "kilo": Path(os.environ["HOME"]) / ".config" / "kilo" / "agent",
    "codex": Path(os.environ["HOME"]) / ".codex" / "agents",
}

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
    fm = {
        "name": meta["name"],
        "description": meta["description"],
        "model": cfg["model"],
        "effort": cfg.get("effort", meta.get("effort", "medium")),
        "disallowedTools": cfg.get("disallowedTools", ["Agent"]) if meta.get("readonly") == "true" else cfg.get("disallowedTools", ["Agent"]),
        "color": meta.get("color", "blue"),
    }
    # desempacota lista de disallowedTools como string no estilo do Claude
    dt = fm["disallowedTools"]
    if isinstance(dt, list):
        dt = ", ".join(dt)
    header = (
        "---\n"
        f"name: {fm['name']}\n"
        f"description: {fm['description']}\n"
        f"model: {fm['model']}\n"
        f"effort: {fm['effort']}\n"
        f"disallowedTools: {dt}\n"
        f"color: {fm['color']}\n"
        "---\n\n"
    )
    return header + body + "\n"


def build_kilo(meta, body, cfg):
    model = cfg["model"]  # provider/model, ex: anthropic/claude-sonnet-4.6
    perm_lines = ["  task: deny"]
    if meta.get("readonly") == "true":
        perm_lines.append("  edit: deny")
    header = (
        "---\n"
        f"name: {meta['name']}\n"
        f"description: {meta['description']}\n"
        f"mode: subagent\n"
        f"model: {model}\n"
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cli", nargs="?", help="claude | kilo | codex")
    ap.add_argument("--target", help="diretório de destino (default: padrão do CLI)")
    ap.add_argument("--list", action="store_true", help="mostra CLIs e destinos")
    args = ap.parse_args()

    if args.list or not args.cli:
        print("CLIs suportados:")
        for cli, dest in DEFAULT_TARGETS.items():
            print(f"  {cli:8} -> {dest}")
        return 0

    cli = args.cli
    if cli not in BUILDERS:
        print(f"CLI desconhecido: {cli}", file=sys.stderr)
        return 1

    models = json.loads((CLI_DIR / cli / "models.json").read_text(encoding="utf-8"))
    target = Path(args.target) if args.target else DEFAULT_TARGETS[cli]
    target.mkdir(parents=True, exist_ok=True)

    for role_path in sorted(ROLES_DIR.glob("*.md")):
        meta, body = parse_role(role_path)
        cfg = models[meta["name"]]
        content = BUILDERS[cli](meta, body, cfg)
        out = target / f"{meta['name']}{EXT[cli]}"
        out.write_text(content, encoding="utf-8")
        print(f"  {out}  ({meta['name']})")

    print(f"\nGerados {len(list(target.glob(f'*{EXT[cli]}')))} agentes em {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
