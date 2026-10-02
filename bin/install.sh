#!/usr/bin/env bash
# install.sh — configura TUDO que é necessário para as skills deste repo funcionarem em
# qualquer CLI de IA instalado nesta máquina (claude, kilo, codex, gemini, opencode).
#
# O que faz, por CLI detectado (via `command -v`):
#   claude   -> bin/sync-skills.sh claude   + arquiteto/bin/sync-agents.sh claude
#   kilo     -> bin/sync-skills.sh kilo     + arquiteto/bin/sync-agents.sh kilo
#   codex    -> bin/sync-skills.sh codex    + arquiteto/bin/sync-agents.sh codex
#   gemini   -> bin/sync-skills.sh gemini   + arquiteto/bin/sync-agents.sh gemini
#   opencode -> arquiteto/bin/sync-agents.sh opencode
#              + bin/sync-skills.sh claude (o opencode lê skills nativamente de
#                ~/.claude/skills — compatibilidade oficial com Claude Code — não
#                precisa do binário `claude` instalado, só do diretório)
#              + garante DeepSeek como modelo default em ~/.config/opencode/opencode.jsonc
#                (só escreve "model" se o arquivo não existir ou ainda não tiver essa
#                chave — nunca sobrescreve config já customizada pelo usuário)
#
# Nenhum CLI detectado -> imprime aviso e sai com sucesso (não é erro).
# Idempotente: pode rodar quantas vezes quiser.
#
# NÃO instala dependências de skills individuais (jq, glab, oc etc.) — cada skill que
# precisa disso tem sua própria skill de instalação.
# NÃO regenera arquiteto/dist/ — isso é passo de manutenção do repo (build-agents.py),
# já commitado; este script só instala o que já está commitado.
#
# Uso:
#   bin/install.sh              # detecta e configura tudo
#   bin/install.sh --dry-run    # só mostra o que faria
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="apply"
[[ "${1:-}" == "--dry-run" ]] && MODE="dry-run"

FOUND=()
MISSING=()
CLAUDE_SKILLS_SYNCED=0

log() { echo ">> $*"; }

sync_skills_for() {
  local cli="$1"
  if [ "$MODE" = "dry-run" ]; then
    log "bin/sync-skills.sh $cli --dry-run"
    "$REPO_DIR/bin/sync-skills.sh" "$cli" --dry-run
  else
    log "bin/sync-skills.sh $cli"
    "$REPO_DIR/bin/sync-skills.sh" "$cli"
  fi
  if [[ "$cli" == "claude" ]]; then
    CLAUDE_SKILLS_SYNCED=1
  fi
}

sync_agents_for() {
  local cli="$1"
  if [ "$MODE" = "dry-run" ]; then
    log "arquiteto/bin/sync-agents.sh $cli --dry-run"
    "$REPO_DIR/arquiteto/bin/sync-agents.sh" "$cli" --dry-run
  else
    log "arquiteto/bin/sync-agents.sh $cli"
    "$REPO_DIR/arquiteto/bin/sync-agents.sh" "$cli"
  fi
}

configure_opencode_deepseek_default() {
  local config_dir="$HOME/.config/opencode"
  local config_path="$config_dir/opencode.jsonc"

  if [ ! -f "$config_path" ]; then
    log "opencode: criando $config_path com modelo default DeepSeek"
    if [ "$MODE" = "apply" ]; then
      mkdir -p "$config_dir"
      cat > "$config_path" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "model": "deepseek/deepseek-v4-flash"
}
EOF
    fi
    return 0
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo "  AVISO: jq não encontrado — não foi possível checar/definir o modelo default do opencode em $config_path. Instale jq e rode de novo, ou edite manualmente." >&2
    return 0
  fi

  if jq -e 'has("model")' "$config_path" >/dev/null 2>&1; then
    log "opencode: $config_path já tem \"model\" definido — não sobrescrevendo."
    return 0
  fi

  log "opencode: adicionando \"model\": \"deepseek/deepseek-v4-flash\" em $config_path"
  if [ "$MODE" = "apply" ]; then
    local tmp; tmp="$(mktemp)"
    jq '. + {"model": "deepseek/deepseek-v4-flash"}' "$config_path" > "$tmp"
    mv "$tmp" "$config_path"
  fi
}

echo "=== install.sh — detectando CLIs instalados ==="

for cli in claude kilo codex gemini opencode; do
  if command -v "$cli" >/dev/null 2>&1 || { [ "$cli" = "gemini" ] && command -v agy >/dev/null 2>&1; }; then
    FOUND+=("$cli")
  else
    MISSING+=("$cli")
  fi
done

echo "Detectados: ${FOUND[*]:-nenhum}"
echo "Não encontrados: ${MISSING[*]:-nenhum}"
echo

if [ "${#FOUND[@]}" -eq 0 ]; then
  echo "Nenhum CLI de IA suportado (claude|kilo|codex|gemini|opencode) encontrado no PATH. Nada a fazer."
  exit 0
fi

for cli in "${FOUND[@]}"; do
  echo "--- $cli ---"
  case "$cli" in
    claude|kilo|codex|gemini)
      sync_skills_for "$cli"
      sync_agents_for "$cli"
      ;;
    opencode)
      sync_agents_for "opencode"
      if [ "$CLAUDE_SKILLS_SYNCED" -eq 0 ]; then
        log "opencode lê skills nativamente de ~/.claude/skills (compat Claude Code) — sincronizando esse diretório mesmo sem o binário claude instalado"
        sync_skills_for "claude"
      fi
      configure_opencode_deepseek_default
      ;;
  esac
  echo
done

echo "=== dist/ dos subagentes (informativo — não regenerado por este script) ==="
if command -v python3 >/dev/null 2>&1; then
  python3 "$REPO_DIR/arquiteto/bin/build-agents.py" --check || {
    echo "AVISO: arquiteto/dist/ está desatualizado em relação a roles/+models.json. Isso é responsabilidade de quem mantém o repo (rodar build-agents.py e commitar dist/), não deste install.sh — os symlinks acima apontam para o dist/ como ele está agora." >&2
  }
else
  echo "AVISO: python3 não encontrado — não foi possível checar drift de arquiteto/dist/." >&2
fi

echo
echo "Feito ($MODE). CLIs configurados: ${FOUND[*]}."
