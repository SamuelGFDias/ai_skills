#!/usr/bin/env bash
# sync-skills.sh — (re)cria as skills deste repo nos locais que cada CLI de IA espera.
#
# Em vez de symlink, copia o conteúdo de cada skill — o destino fica sempre como uma cópia
# fiel e descartável, recriada a cada run.
#
# Alvos (primeiro argumento posicional, default "all"):
#   claude  -> copia cada skill (diretório com SKILL.md na raiz) para ~/.claude/skills/<nome>,
#              apagando e recriando o destino a cada run; remove cópias órfãs (skill removida do repo).
#   kilo    -> garante que ~/.config/kilo/kilo.jsonc tenha o caminho deste repo em "skills.paths"
#              (o Kilo lê os SKILL.md direto da fonte, não precisa de cópia).
#
# Uso:
#   bin/sync-skills.sh                  # aplica em claude + kilo
#   bin/sync-skills.sh claude           # aplica só no Claude Code
#   bin/sync-skills.sh kilo             # aplica só no Kilo
#   bin/sync-skills.sh all --dry-run    # só mostra o que faria
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${1:-all}"
MODE="apply"
[[ "${2:-}" == "--dry-run" || "${1:-}" == "--dry-run" ]] && MODE="dry-run"
[[ "$CLI" == "--dry-run" ]] && CLI="all"

sync_claude() {
  local target_dir="$HOME/.claude/skills"
  [ "$MODE" = "apply" ] && mkdir -p "$target_dir"

  local names=()
  for skill_dir in "$REPO_DIR"/*/; do
    [ -f "$skill_dir/SKILL.md" ] || continue
    local name; name="$(basename "$skill_dir")"
    names+=("$name")
    local dest="$target_dir/$name"
    echo "$MODE: recria $dest <- $skill_dir"
    if [ "$MODE" = "apply" ]; then
      rm -rf "$dest"
      cp -R "$skill_dir" "$dest"
    fi
  done

  [ -d "$target_dir" ] || return 0
  for existing in "$target_dir"/*/; do
    [ -d "$existing" ] || continue
    local name; name="$(basename "$existing")"
    local found=0
    for n in "${names[@]:-}"; do [ "$n" = "$name" ] && found=1 && break; done
    if [ "$found" -eq 0 ]; then
      echo "$MODE: rm $existing (órfão — $name não é mais skill)"
      [ "$MODE" = "apply" ] && rm -rf "$existing"
    fi
  done
}

sync_kilo() {
  local config_path="$HOME/.config/kilo/kilo.jsonc"
  if [ ! -f "$config_path" ]; then
    echo "  AVISO: $config_path não existe — pulando configuração do Kilo." >&2
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "  AVISO: jq não encontrado — pulando configuração do Kilo (edite manualmente skills.paths)." >&2
    return 0
  fi

  if jq -e --arg p "$REPO_DIR" '(.skills.paths // []) | index($p)' "$config_path" >/dev/null 2>&1; then
    echo "kilo.jsonc já aponta para $REPO_DIR — nada a fazer."
    return 0
  fi

  echo "$MODE: adiciona '$REPO_DIR' em skills.paths de $config_path"
  [ "$MODE" = "apply" ] || return 0

  local tmp; tmp="$(mktemp)"
  jq --arg p "$REPO_DIR" '.skills.paths = ((.skills.paths // []) + [$p])' "$config_path" > "$tmp"
  mv "$tmp" "$config_path"
}

case "$CLI" in
  claude) sync_claude ;;
  kilo) sync_kilo ;;
  all) sync_claude; sync_kilo ;;
  *) echo "Alvo inválido: $CLI (use claude, kilo ou all)" >&2; exit 1 ;;
esac

echo "Feito ($MODE)."
