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

# Conjunto mínimo de tools que um papel readonly precisa ter bloqueadas no claude,
# independente do que vier em cli/claude/models.json (usado por build_claude).
READONLY_TOOLS = ("Edit", "Write", "NotebookEdit", "Agent")

# Caracteres de controle que json.dumps(ensure_ascii=False) deixa passar crus mas que
# YAML e TOML não tratam como texto plano seguro (fora de \t \n \r, que são válidos nos dois).
# Faixas por code point (em vez de classe de regex) para não depender de escapes unicode
# no literal do padrão.
_UNSAFE_CONTROL_RANGES = (
    (0x00, 0x08),
    (0x0B, 0x0C),
    (0x0E, 0x1F),
    (0x7F, 0x7F),
    (0x80, 0x9F),
    (0x2028, 0x2028),
    (0x2029, 0x2029),
)


def _find_unsafe_control_char(value: str):
    for ch in value:
        cp = ord(ch)
        for lo, hi in _UNSAFE_CONTROL_RANGES:
            if lo <= cp <= hi:
                return ch
    return None


class BuildError(Exception):
    """Erro de geração com contexto suficiente (papel/arquivo/CLI) para diagnóstico direto,
    sem precisar interpretar um traceback cru de KeyError/JSONDecodeError/etc."""


def parse_role(path: Path):
    """Lê roles/<nome>.md: frontmatter yaml + corpo."""
    # utf-8-sig: tolera BOM (Notepad/editores Windows costumam gravar um) sem que ele
    # vire parte do primeiro "---" e quebre o regex de frontmatter com uma mensagem enganosa.
    text = path.read_text(encoding="utf-8-sig")
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
    if not m:
        raise BuildError(f"frontmatter ausente ou malformado em {path}")
    meta = {}
    for line in m.group(1).splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            meta[k.strip()] = v.strip()
    body = m.group(2).strip()
    return meta, body


def load_models(cli: str, path: Path):
    """Lê cli/<cli>/models.json com mensagens de erro que citam o caminho do arquivo."""
    try:
        text = path.read_text(encoding="utf-8-sig")
    except FileNotFoundError:
        raise BuildError(f"arquivo de modelos não encontrado para o cli '{cli}': {path}")
    except OSError as e:
        raise BuildError(f"não foi possível ler {path}: {e}")
    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        raise BuildError(f"JSON inválido em {path}: {e}")


def is_readonly(meta: dict) -> bool:
    """Normaliza o campo 'readonly' do frontmatter (só esse campo — não é um parser YAML genérico)."""
    return meta.get("readonly", "").strip().lower() == "true"


def quote_str(value: str) -> str:
    """Serializa uma string como escalar válido tanto em YAML double-quoted (claude/kilo)
    quanto em TOML basic string (codex) — os escapes de json.dumps cabem nos dois formatos.
    Não é um serializador YAML genérico: só cobre o caso escalar-string usado aqui.
    """
    bad = _find_unsafe_control_char(value)
    if bad is not None:
        raise BuildError(
            f"valor contém caractere de controle não suportado (U+{ord(bad):04X}) "
            f"para serialização YAML/TOML: {value!r}"
        )
    return json.dumps(value, ensure_ascii=False)


def build_claude(meta, body, cfg, role_path):
    name = meta["name"]
    dt_cfg = cfg.get("disallowedTools", ["Agent"])
    if isinstance(dt_cfg, str):
        dt_list = [t.strip() for t in dt_cfg.split(",") if t.strip()]
    else:
        dt_list = list(dt_cfg)

    if is_readonly(meta):
        # União — nunca deixar cfg (models.json) reduzir o bloqueio de um papel readonly.
        merged = list(dt_list)
        for t in READONLY_TOOLS:
            if t not in merged:
                merged.append(t)
        dt_list = merged
        missing = [t for t in READONLY_TOOLS if t not in dt_list]
        if missing:
            raise BuildError(
                f"papel '{name}' ({role_path}) é readonly mas disallowedTools final "
                f"não bloqueia {missing} — verifique a lógica de união em build_claude"
            )

    dt = ", ".join(dt_list)
    header = (
        "---\n"
        f"name: {name}\n"
        f"description: {quote_str(meta['description'])}\n"
        f"model: {cfg['model']}\n"
        f"effort: {cfg.get('effort', meta.get('effort', 'medium'))}\n"
        f"disallowedTools: {dt}\n"
        f"color: {cfg.get('color', meta.get('color', 'blue'))}\n"
        "---\n\n"
    )
    return header + body + "\n"


def build_kilo(meta, body, cfg, role_path):
    perm_lines = ["  task: deny"]
    if is_readonly(meta):
        perm_lines.append("  edit: deny")
    header = (
        "---\n"
        f"name: {meta['name']}\n"
        f"description: {quote_str(meta['description'])}\n"
        f"mode: subagent\n"
        f"model: {cfg['model']}\n"
        "permission:\n" + "\n".join(perm_lines) + "\n"
        "---\n\n"
    )
    return header + body + "\n"


def build_codex(meta, body, cfg, role_path):
    if "'''" in body:
        raise BuildError(
            f"papel '{meta['name']}' ({role_path}): corpo contém `'''`, incompatível com "
            "TOML multi-line literal string — remova ou escape antes de gerar o codex"
        )
    sandbox = cfg.get("sandbox", "read-only" if is_readonly(meta) else "workspace-write")
    reasoning = cfg.get("reasoning", "medium")
    toml = (
        f'name = {quote_str(meta["name"])}\n'
        f'description = {quote_str(meta["description"])}\n'
        f'model = {quote_str(cfg["model"])}\n'
        f'model_reasoning_effort = {quote_str(reasoning)}\n'
        f'sandbox_mode = {quote_str(sandbox)}\n'
        # ''' (literal string) em vez de """ (basic string): o corpo do role é injetado
        # cru e pode conter '\' (regex, caminhos Windows) ou aspas que corromperiam um
        # basic string TOML silenciosamente.
        f"developer_instructions = '''\n{body}\n'''\n"
    )
    return toml


BUILDERS = {"claude": build_claude, "kilo": build_kilo, "codex": build_codex}
EXT = {"claude": ".md", "kilo": ".md", "codex": ".toml"}


def build_cli(cli):
    """Retorna {nome_arquivo: conteudo} para um CLI."""
    models_path = CLI_DIR / cli / "models.json"
    models = load_models(cli, models_path)
    out = {}
    seen_names = {}
    for role_path in sorted(ROLES_DIR.glob("*.md")):
        meta, body = parse_role(role_path)
        try:
            name = meta["name"]
        except KeyError:
            raise BuildError(f"{role_path}: frontmatter sem campo obrigatório 'name'")

        if name in seen_names:
            raise BuildError(
                f"nome de papel duplicado '{name}': definido em {seen_names[name]} e em {role_path}"
            )
        seen_names[name] = role_path

        if name not in models:
            raise BuildError(
                f"papel '{name}' (definido em {role_path}) não tem entrada em {models_path}"
            )
        cfg = models[name]

        try:
            content = BUILDERS[cli](meta, body, cfg, role_path)
        except BuildError:
            raise
        except KeyError as e:
            raise BuildError(
                f"papel '{name}' ({role_path}), cli '{cli}' ({models_path}): "
                f"campo obrigatório {e} ausente"
            )
        out[f"{name}{EXT[cli]}"] = content
    return out


def check_drift(cli):
    """Verifica se dist/<cli> está em dia com roles/ + cli/<cli>/models.json. Retorna 0 se ok, 2 se drift."""
    generated = build_cli(cli)
    target = DIST_DIR / cli

    # dist/<cli>/ é 100% gerado por este script — não deve conter arquivos manuais.
    # Por isso qualquer arquivo presente aqui que este build não gerou é órfão,
    # independente da extensão (um .md sobrando num cli que agora gera .toml também conta).
    if target.exists():
        orphans = sorted(f.name for f in target.iterdir() if f.is_file() and f.name not in generated)
    else:
        orphans = []

    drift = []
    for name, content in generated.items():
        path = target / name
        if not path.exists():
            drift.append(f"  FALTA: {name}")
        elif path.read_text(encoding="utf-8") != content:
            drift.append(f"  DIVERGE: {name}")
    if orphans:
        drift.append("  ÓRFÃOS (não gerados mais): " + ", ".join(orphans))

    # Aviso não-fatal (não conta como drift): entradas em models.json sem papel
    # correspondente em roles/ — pode ser um papel removido sem limpar o models.json.
    models_path = CLI_DIR / cli / "models.json"
    models = load_models(cli, models_path)
    known_roles = set()
    for role_path in ROLES_DIR.glob("*.md"):
        meta, _ = parse_role(role_path)
        if "name" in meta:
            known_roles.add(meta["name"])
    orphan_model_keys = sorted(k for k in models if not k.startswith("_") and k not in known_roles)

    if drift:
        print(f"DRIFT em {target}:")
        print("\n".join(drift))
        print(f"Rode 'python3 build-agents.py {cli}' e commite dist/.")
        if orphan_model_keys:
            print(f"  AVISO: entradas em {models_path} sem papel correspondente em roles/: " + ", ".join(orphan_model_keys))
        return 2

    print(f"OK: dist/{cli} em dia com roles/ + cli/{cli}/models.json")
    if orphan_model_keys:
        print(f"  AVISO: entradas em {models_path} sem papel correspondente em roles/: " + ", ".join(orphan_model_keys))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cli", nargs="?", help="claude | kilo | codex")
    ap.add_argument("--target", help="destino alternativo (default: arquiteto/dist/<cli>); não se aplica a --check")
    ap.add_argument("--list", action="store_true", help="mostra CLIs suportados")
    ap.add_argument("--check", action="store_true", help="verifica drift entre roles+models e dist/")
    args = ap.parse_args()

    try:
        if args.check:
            if args.target:
                ap.error(
                    "--target não se aplica a --check: o alvo do check é sempre dist/<cli>/. "
                    "Rode '--check' sem --target, ou gere num destino pontual com '<cli> --target <dir>' "
                    "(sem --check)."
                )
            clis = [args.cli] if args.cli else sorted(BUILDERS)
            for c in clis:
                if c not in BUILDERS:
                    raise BuildError(f"CLI desconhecido: '{c}' (suportados: {', '.join(sorted(BUILDERS))})")
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
            raise BuildError(f"CLI desconhecido: '{cli}' (suportados: {', '.join(sorted(BUILDERS))})")

        generated = build_cli(cli)
        target = Path(args.target) if args.target else DIST_DIR / cli
        target.mkdir(parents=True, exist_ok=True)
        for name, content in generated.items():
            path = target / name
            # newline="\n": força LF no arquivo escrito independente do SO, para o
            # conteúdo commitado em dist/ ser determinístico entre Linux e Windows.
            with path.open("w", encoding="utf-8", newline="\n") as fh:
                fh.write(content)
            print(f"  {path}  ({name})")
        print(f"\nGerados {len(generated)} agentes em {target} — commite dist/.")
        return 0
    except BuildError as e:
        print(f"Erro: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
