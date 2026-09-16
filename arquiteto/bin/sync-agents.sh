#!/usr/bin/env bash
# sync-agents.sh — instala os agentes do arquiteto no diretório real de cada CLI,
# por symlink apontando para a config COMMITADA em arquiteto/dist/<cli>/.
#
# Por que symlink? Os agentes gerados são versionados no repo. Um git pull
# atualiza o conteúdo apontado; o symlink sempre reflete a última versão —
# sem rodar gerador nem copiar arquivos na mão.
#
# Uso:
#   bin/sync-agents.sh                   # cria/atualiza symlinks em todos os CLIs
#   bin/sync-agents.sh claude            # só um CLI (claude|kilo|codex|gemini|opencode)
#   bin/sync-agents.sh --dry-run         # só mostra o que faria (todos os CLIs)
#   bin/sync-agents.sh claude --dry-run  # só mostra o que faria (um CLI)
#   bin/sync-agents.sh --check           # valida drift do dist (roles+models vs commitado), todos os CLIs
#   bin/sync-agents.sh --check claude    # valida drift de um CLI só
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$REPO_DIR/dist"

# alvo real de cada CLI:  dist/<cli> -> <dir real>/<arquivo>
declare -A TARGETS=(
  [claude]="$HOME/.claude/agents"
  [kilo]="$HOME/.config/kilo/agent"
  [codex]="$HOME/.codex/agents"
  [gemini]="$HOME/.gemini/agents"
  [opencode]="$HOME/.config/opencode/agent"
)

ALL_CLIS=(claude kilo codex gemini opencode)

# --check pode vir em qualquer posição ($1 ou $2), seguido opcionalmente do nome do cli
if [[ "${1:-}" == "--check" || "${2:-}" == "--check" ]]; then
  cli_arg=""
  for a in "$@"; do
    [[ "$a" == "--check" ]] && continue
    cli_arg="$a"
  done
  if [[ -n "$cli_arg" ]]; then
    python3 "$REPO_DIR/bin/build-agents.py" --check "$cli_arg" || exit $?
  else
    python3 "$REPO_DIR/bin/build-agents.py" --check || exit $?
  fi
  exit 0
fi

MODE="apply"
CLI_FILTER=""
for a in "$@"; do
  if [[ "$a" == "--dry-run" ]]; then
    MODE="dry-run"
  else
    CLI_FILTER="$a"
  fi
done

if [[ -n "$CLI_FILTER" ]]; then
  if [[ -z "${TARGETS[$CLI_FILTER]+x}" ]]; then
    echo "CLI desconhecido: '$CLI_FILTER' (use: ${ALL_CLIS[*]})" >&2
    exit 1
  fi
  CLIS=("$CLI_FILTER")
else
  CLIS=("${ALL_CLIS[@]}")
fi

for cli in "${CLIS[@]}"; do
  src="$DIST_DIR/$cli"
  dst="${TARGETS[$cli]}"
  [ -d "$src" ] || { echo "  AVISO: sem dist/$cli — rode build-agents.py e commite." >&2; continue; }
  mkdir -p "$dst"
  for file in "$src"/*; do
    [ -f "$file" ] || continue
    name="$(basename "$file")"
    link="$dst/$name"
    if [ -L "$link" ] && [ "$(readlink "$link")" = "$file" ]; then
      continue  # já ok
    fi
    if [ -e "$link" ] && [ ! -L "$link" ]; then
      echo "  AVISO: $link existe e não é symlink — removendo (era gerado à mão)." >&2
      [ "$MODE" = "apply" ] && rm -f "$link"
    fi
    echo "$MODE: ln -s $file $link"
    [ "$MODE" = "apply" ] && ln -sfn "$file" "$link"
  done

  # segunda passada: remove symlinks órfãos — criados por este script (apontam
  # para dentro de $src) mas cujo arquivo de origem não existe mais.
  for link in "$dst"/*; do
    [ -L "$link" ] || continue
    target="$(readlink "$link")"
    case "$target" in
      "$src"/*) : ;;
      *) continue ;;  # não é nosso — não toca
    esac
    [ -e "$target" ] && continue  # destino ainda existe, ok
    echo "$MODE: rm $link  # órfão, apontava para $target"
    [ "$MODE" = "apply" ] && { rm -f "$link"; echo "  removido órfão: $link"; }
  done
done

echo "Feito ($MODE)."
