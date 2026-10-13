#!/usr/bin/env python3
"""Gera cli/<cli>/models.local.json (override pessoal, não versionado) a partir de models.json.

O arquivo gerado traz só os campos de modelo/esforço (model, effort, reasoning) dos papéis
escolhidos, prontos para editar. Papéis presentes no arquivo viram arquivo real no destino pelo
bin/sync-agents.sh (não acompanham mais o git pull) — por isso, deixe só os que você quer mudar.

Uso:
  init-local-models.py <cli>                          # todos os papéis (apague os que não vai mudar)
  init-local-models.py <cli> executor-padrao revisor-padrao   # só esses papéis
  init-local-models.py <cli> --force                  # sobrescreve um models.local.json existente
Depois: edite o arquivo e rode bin/sync-agents.sh <cli>.
"""
import argparse
import json
import sys
from pathlib import Path

CLI_DIR = Path(__file__).resolve().parent.parent / "cli"
FIELDS = ("model", "effort", "reasoning")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cli")
    ap.add_argument("roles", nargs="*", help="papéis a incluir (default: todos)")
    ap.add_argument("--force", action="store_true", help="sobrescreve models.local.json existente")
    args = ap.parse_args()

    base_path = CLI_DIR / args.cli / "models.json"
    if not base_path.exists():
        print(f"Erro: CLI desconhecido ou sem models.json: {base_path}", file=sys.stderr)
        return 1
    base = json.loads(base_path.read_text(encoding="utf-8-sig"))
    known = [k for k in base if not k.startswith("_")]

    unknown = [r for r in args.roles if r not in known]
    if unknown:
        print(f"Erro: papéis inexistentes: {', '.join(unknown)} (disponíveis: {', '.join(known)})", file=sys.stderr)
        return 1

    out_path = CLI_DIR / args.cli / "models.local.json"
    if out_path.exists() and not args.force:
        print(f"Erro: {out_path} já existe (use --force para sobrescrever)", file=sys.stderr)
        return 1

    out = {"_comment": "Override pessoal, não versionado. Só os papéis listados aqui são sobrescritos; "
                       "apague os que não quer mudar. Aplique com bin/sync-agents.sh " + args.cli}
    for role in args.roles or known:
        out[role] = {k: v for k, v in base[role].items() if k in FIELDS}

    with out_path.open("w", encoding="utf-8", newline="\n") as fh:
        fh.write(json.dumps(out, indent=2, ensure_ascii=False) + "\n")
    print(f"Gerado {out_path} com {len(out) - 1} papel(is). Edite e rode: bin/sync-agents.sh {args.cli}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
