#!/usr/bin/env bash
# sync-symlinks.sh — mantém ~/.claude/skills em paridade com o repo ai_skills.
#
# - Cria symlink em ~/.claude/skills/<nome> -> <repo>/<nome> para cada diretório com SKILL.md.
# - Remove symlinks órfãos (apontam para o repo mas o diretório/SKILL.md não existe mais).
# - Idempotente; pode rodar a qualquer momento.
#
# Uso:
#   bin/sync-symlinks.sh            # aplica (cria + remove)
#   bin/sync-symlinks.sh --dry-run  # só mostra o que faria
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$HOME/.claude/skills"
MODE="apply"

if [[ "${1:-}" == "--dry-run" ]]; then
  MODE="dry-run"
fi

mkdir -p "$TARGET_DIR"

# 1) Cria/atualiza symlinks para cada skill (diretório com SKILL.md na raiz)
for skill_dir in "$REPO_DIR"/*/; do
  [ -f "$skill_dir/SKILL.md" ] || continue
  name="$(basename "$skill_dir")"
  link="$TARGET_DIR/$name"
  if [ -L "$link" ] && [ "$(readlink "$link")" = "$skill_dir" ]; then
    continue  # já ok
  fi
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    echo "  AVISO: $link existe e não é symlink — pulando (resolver manualmente)." >&2
    continue
  fi
  echo "$MODE: ln -s $skill_dir $link"
  [ "$MODE" = "apply" ] && ln -sfn "$skill_dir" "$link"
done

# 2) Remove symlinks órfãos (apontam para dentro do repo, mas o alvo não é mais skill)
for link in "$TARGET_DIR"/*; do
  [ -L "$link" ] || continue
  target="$(readlink "$link")"
  case "$target" in
    "$REPO_DIR"/*)
      name="$(basename "$link")"
      if [ ! -f "$REPO_DIR/$name/SKILL.md" ]; then
        echo "$MODE: rm $link (órfão — $name não é mais skill)"
        [ "$MODE" = "apply" ] && rm "$link"
      fi
      ;;
  esac
done

echo "Feito ($MODE)."
