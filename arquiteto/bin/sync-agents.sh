#!/usr/bin/env bash
# sync-agents.sh — instala os agentes do arquiteto no diretório real de cada CLI,
# por symlink apontando para a config COMMITADA em arquiteto/dist/<cli>/.
#
# Por que symlink? Os agentes gerados são versionados no repo. Um git pull
# atualiza o conteúdo apontado; o symlink sempre reflete a última versão —
# sem rodar gerador nem copiar arquivos na mão.
#
# Uso:
#   bin/sync-agents.sh                # cria/atualiza symlinks em todos os CLIs
#   bin/sync-agents.sh --dry-run      # só mostra o que faria
#   bin/sync-agents.sh --check        # valida drift do dist (roles+models vs commitado)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$REPO_DIR/dist"
MODE="apply"

if [[ "${1:-}" == "--dry-run" ]]; then MODE="dry-run"; fi

# alvo real de cada CLI:  dist/<cli> -> <dir real>/<arquivo>
declare -A TARGETS=(
  [claude]="$HOME/.claude/agents"
  [kilo]="$HOME/.config/kilo/agent"
  [codex]="$HOME/.codex/agents"
)

if [[ "${1:-}" == "--check" ]]; then
  python3 "$REPO_DIR/bin/build-agents.py" --check || exit $?
  exit 0
fi

for cli in "${!TARGETS[@]}"; do
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
