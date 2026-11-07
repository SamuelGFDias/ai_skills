#!/usr/bin/env bash
# sync-skills.sh — (re)cria as skills deste repo nos locais que cada CLI de IA espera.
#
# Linux/macOS/WSL: destino vira symlink para a skill (ln -s nativo funciona sem ressalva).
# Git Bash/MSYS/Cygwin (Windows): destino vira cópia — sem Developer Mode + winsymlinks:nativestrict,
# `ln -s` no MSYS apenas copia o arquivo em vez de linkar de verdade (ver AGENTS.md, "Armadilhas no
# Windows"), então symlink nesse ambiente vira uma cópia disfarçada e some no próximo `git pull` sem
# rodar o sync de novo — cópia explícita evita essa falsa promessa. Detecção via `uname -s`;
# sobrescreva com FORCE_LINK_MODE=copy|symlink para testar o outro modo manualmente.
#
# Alvos (primeiro argumento posicional, default "all"):
#   claude  -> linka (Linux/macOS/WSL) ou copia (Windows/Git Bash) cada skill (diretório com
#              SKILL.md na raiz) para ~/.claude/skills/<nome>, recriando o destino a cada run;
#              remove só symlinks quebrados (skill removida do repo); diretórios reais e
#              symlinks válidos que não são do repo são mantidos, com aviso.
#   kilo   -> garante que ~/.config/kilo/kilo.jsonc tenha o caminho deste repo em "skills.paths"
#              (o Kilo lê os SKILL.md direto da fonte, não precisa de cópia nem symlink).
#   codex   -> linka/copia (mesmo critério de claude) cada skill para ~/.agents/skills/<nome> —
#              diretório de escopo de usuário que o Codex CLI escaneia nativamente (skills
#              auto-descobertas, mesmo formato de SKILL.md com frontmatter name+description); a
#              doc oficial confirma suporte a pastas symlinkadas nesse local.
#   gemini  -> Gemini CLI não tem diretório solto de skills: o mecanismo oficial é uma extension
#              em ~/.gemini/extensions/<nome>/ com manifesto gemini-extension.json e as skills
#              dentro de skills/<nome>/SKILL.md da própria extension. Por isso mantemos aqui uma
#              extension própria "ai-skills" em ~/.gemini/extensions/ai-skills/, com manifesto
#              mínimo, e sincronizamos as skills para dentro de extensions/ai-skills/skills/.
#
# Nota sobre opencode: NÃO tem alvo próprio aqui de propósito. A doc oficial confirma que o
# opencode já lê skills nativamente de ~/.claude/skills/ (compat nativa com Claude Code, ligada
# por padrão, desativável via OPENCODE_DISABLE_CLAUDE_CODE_SKILLS) — rodar o alvo "claude" já é
# suficiente, mesmo em máquina sem o binário `claude` instalado (sync_claude só escreve um
# diretório). Não recriar um alvo "opencode" aqui.
#
# Uso:
#   bin/sync-skills.sh                  # aplica em claude + kilo + codex + gemini
#   bin/sync-skills.sh claude           # aplica só no Claude Code
#   bin/sync-skills.sh kilo             # aplica só no Kilo
#   bin/sync-skills.sh codex            # aplica só no Codex CLI
#   bin/sync-skills.sh gemini           # aplica só na extension do Gemini CLI
#   bin/sync-skills.sh all --dry-run    # só mostra o que faria
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${1:-all}"
MODE="apply"
[[ "${2:-}" == "--dry-run" || "${1:-}" == "--dry-run" ]] && MODE="dry-run"
[[ "$CLI" == "--dry-run" ]] && CLI="all"

if [ -n "${FORCE_LINK_MODE:-}" ]; then
  LINK_MODE="$FORCE_LINK_MODE"
else
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) LINK_MODE="copy" ;;
    *) LINK_MODE="symlink" ;;
  esac
fi
case "$LINK_MODE" in
  copy|symlink) ;;
  *) echo "FORCE_LINK_MODE inválido: $LINK_MODE (use copy ou symlink)" >&2; exit 1 ;;
esac

# sync_skill_dir_target <target_dir>
# (Re)cria em $target_dir uma entrada por skill do repo (symlink ou cópia,
# conforme $LINK_MODE) e remove entradas órfãs (skill removida do repo).
# Usado por sync_claude, sync_codex e sync_gemini (que aponta para dentro
# da própria extension em vez de direto no HOME).
sync_skill_dir_target() {
  local target_dir="$1"
  [ "$MODE" = "apply" ] && mkdir -p "$target_dir"

  local names=()
  for skill_dir in "$REPO_DIR"/*/; do
    [ -f "$skill_dir/SKILL.md" ] || continue
    local name; name="$(basename "$skill_dir")"
    names+=("$name")
    local dest="$target_dir/$name"
    local src="${skill_dir%/}"
    if [ "$LINK_MODE" = "symlink" ]; then
      echo "$MODE ($LINK_MODE): $dest -> $src"
      if [ "$MODE" = "apply" ]; then
        rm -rf "$dest"
        ln -s "$src" "$dest"
      fi
    else
      echo "$MODE ($LINK_MODE): recria $dest <- $skill_dir"
      if [ "$MODE" = "apply" ]; then
        rm -rf "$dest"
        cp -R "$skill_dir" "$dest"
      fi
    fi
  done

  [ -d "$target_dir" ] || return 0
  for existing in "$target_dir"/*; do
    # -d segue symlink (pega diretórios e symlinks válidos para diretório);
    # -L pega symlink quebrado (repo renomeou/removeu a skill) — sem isso o órfão fica preso.
    [ -d "$existing" ] || [ -L "$existing" ] || continue
    local name; name="$(basename "$existing")"
    local found=0
    for n in "${names[@]:-}"; do [ "$n" = "$name" ] && found=1 && break; done
    if [ "$found" -eq 0 ]; then
      # Só symlink quebrado é seguro de apagar: foi criado por este script e o repo removeu a
      # skill. Diretório real ou symlink válido pode ser skill instalada por outra ferramenta
      # (ex.: find-skills, codebase-memory) e nunca é removido aqui. No modo cópia (Windows)
      # o destino é diretório real e não dá para distinguir cópia nossa de skill externa:
      # só avisa.
      if [ -L "$existing" ] && [ ! -e "$existing" ]; then
        echo "$MODE: rm $existing (symlink quebrado — $name não é mais skill)"
        [ "$MODE" = "apply" ] && rm -f "$existing"
      else
        echo "AVISO: $existing não é skill deste repo e foi mantido (só symlink quebrado é removido)" >&2
      fi
    fi
  done
}

sync_claude() {
  sync_skill_dir_target "$HOME/.claude/skills"
}

sync_codex() {
  sync_skill_dir_target "$HOME/.agents/skills"
}

sync_gemini() {
  local ext_dir="$HOME/.gemini/extensions/ai-skills"
  local manifest="$ext_dir/gemini-extension.json"

  if [ "$MODE" = "apply" ]; then
    mkdir -p "$ext_dir"
    cat > "$manifest" <<'EOF'
{
  "name": "ai-skills",
  "version": "1.0.0"
}
EOF
  else
    echo "$MODE: escreveria $manifest"
  fi

  sync_skill_dir_target "$ext_dir/skills"

  local config_dir="$HOME/.gemini/config"
  if [ "$MODE" = "apply" ]; then
    mkdir -p "$config_dir"
    if [ "$LINK_MODE" = "symlink" ]; then
      ln -sfn "$ext_dir/skills" "$config_dir/skills"
    else
      sync_skill_dir_target "$config_dir/skills"
    fi
    cat > "$config_dir/skills.json" <<EOF
{
  "entries": [
    {
      "path": "$REPO_DIR"
    }
  ]
}
EOF
  else
    echo "$MODE: configuraria $config_dir/skills e $config_dir/skills.json"
  fi
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
  codex) sync_codex ;;
  gemini) sync_gemini ;;
  all) sync_claude; sync_kilo; sync_codex; sync_gemini ;;
  *) echo "Alvo inválido: $CLI (use claude, kilo, codex, gemini ou all)" >&2; exit 1 ;;
esac

echo "Feito ($MODE)."
