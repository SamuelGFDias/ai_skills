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
#   Instruções globais (arquivo que o agente lê em toda sessão): delegado a
#   bin/sync-global-config.sh. Cada skill pode ter um global.md; você escolhe quais ligar (pergunta
#   interativa na primeira vez; a escolha fica em ~/.config/ai/skills-global.conf). claude e gemini
#   recebem só um `@ai-skills.md` e o conteúdo vai para um arquivo próprio no diretório global;
#   codex e opencode não importam arquivo, então recebem o bloco inline. Sem terminal, e enquanto
#   houver snippet sem escolha, nada é alterado; com --yes, o snippet sem escolha entra ligado (S)
#   sem perguntar. Detalhes: bin/sync-global-config.sh --help.
#   kilo não tem arquivo global mapeado aqui; não é alterado.
#
#   Rotina diária (opt-in, desligada por padrão: só com --schedule, --time ou --days): registra
#   `git pull --ff-only` + re-sync via bin/update-daily.sh numa entrada
#   de crontab marcada (`# ai-skills update-daily`). Instala/atualiza a MESMA entrada a cada run
#   (nunca duplica) e não toca no resto do crontab do usuário. Parametrizável:
#     AI_SKILLS_UPDATE_TIME=HH:MM        hora                      (default 09:00)
#     AI_SKILLS_UPDATE_DAYS=1-5          dias cron 0-6, * (todos)  (default *)
#     AI_SKILLS_UPDATE_SYNC=0            não roda o sync após pull (default 1)
#     AI_SKILLS_LOG_DIR=...              pasta do log  (default ~/.local/state/ai-skills)
#   Log: $AI_SKILLS_LOG_DIR/update-daily.log. Sem `crontab` (Windows/Git Bash, disco sem cron):
#   imprime aviso e segue o resto do install. Flags: --schedule, --time HH:MM, --days, --no-schedule,
#   --uninstall (remove a entrada), --status (log + entrada atual + estado do repo).
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
#   bin/install.sh                        # detecta e configura tudo (sem tocar no cron)
#   bin/install.sh --schedule             # idem, e registra a rotina diária no cron
#   bin/install.sh --dry-run              # só mostra o que faria
#   bin/install.sh --time 07:30 --days 1-5  # registra a rotina em outra hora/dias (implica --schedule)
#   bin/install.sh --no-schedule          # explícito: não registra/atualiza a rotina (é o padrão)
#   bin/install.sh --yes                  # aceita o padrão S nas instruções globais, sem perguntar
#   bin/install.sh --uninstall            # remove a rotina diária (aceita --dry-run)
#   bin/install.sh --status               # mostra o log e o estado da rotina diária
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="apply"
SCHEDULE=0
ACTION="install"
GLOBAL_YES=0
SCHEDULE_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) MODE="dry-run"; shift ;;
    --schedule) SCHEDULE=1; shift ;;
    --no-schedule) SCHEDULE=0; shift ;;
    --yes|-y) GLOBAL_YES=1; shift ;;
    --uninstall) ACTION="uninstall"; shift ;;
    --status) ACTION="status"; shift ;;
    --time|--days)
      [ $# -ge 2 ] || { echo "ERRO: $1 exige um valor (use --help)" >&2; exit 2; }
      SCHEDULE_ARGS+=("$1" "$2")
      SCHEDULE=1
      shift 2
      ;;
    -h|--help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "argumento desconhecido: $1 (use --help)" >&2; exit 2 ;;
  esac
done

FOUND=()
MISSING=()
CLAUDE_SKILLS_SYNCED=0

log() { echo ">> $*"; }

# Rotina diária: sempre delegada a bin/update-daily.sh (lá ficam cron, log, status e notas).
# --repo é sempre explícito: o cron precisa do caminho absoluto deste clone.
schedule_daily_update() {
  if [ ! -f "$REPO_DIR/bin/update-daily.sh" ]; then
    echo "  AVISO: bin/update-daily.sh ausente — rotina diária não registrada." >&2
    return 0
  fi
  bash "$REPO_DIR/bin/update-daily.sh" --repo "$REPO_DIR" "$@"
}

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

# Instruções de uso das skills nos arquivos globais do agente: delegado a
# bin/sync-global-config.sh (seleção por máquina, snippets por skill em <skill>/global.md).
sync_global_config_for() {
  local cli="$1" args=("$1")
  [ "$MODE" = "dry-run" ] && args+=(--dry-run)
  [ "$GLOBAL_YES" -eq 1 ] && args+=(--yes)
  "$REPO_DIR/bin/sync-global-config.sh" "${args[@]}"
}

echo "=== install.sh — detectando CLIs instalados ==="

if [ "$ACTION" = "uninstall" ]; then
  echo "=== rotina diária (crontab) ==="
  args=(--uninstall); [ "$MODE" = "dry-run" ] && args+=(--dry-run)
  schedule_daily_update "${args[@]}" "${SCHEDULE_ARGS[@]}"
  exit $?
fi

if [ "$ACTION" = "status" ]; then
  schedule_daily_update --status "${SCHEDULE_ARGS[@]}"
  exit $?
fi

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

if [ "$SCHEDULE" -eq 1 ]; then
  echo "=== rotina diária (git pull + re-sync via cron) ==="
  args=(--install); [ "$MODE" = "dry-run" ] && args+=(--dry-run)
  schedule_daily_update "${args[@]}" "${SCHEDULE_ARGS[@]}" \
    || echo "  AVISO: não foi possível registrar a rotina diária (ver acima); o restante do install continua." >&2
  echo
fi

if [ "${#FOUND[@]}" -eq 0 ]; then
  echo "Nenhum CLI de IA suportado (claude|kilo|codex|gemini|opencode) encontrado no PATH. Nada mais a fazer."
  exit 0
fi

for cli in "${FOUND[@]}"; do
  echo "--- $cli ---"
  case "$cli" in
    claude|kilo|codex|gemini)
      sync_skills_for "$cli"
      sync_agents_for "$cli"
      # kilo não tem arquivo global mapeado (sync-global-config.sh não o aceita como alvo)
      [ "$cli" = kilo ] || sync_global_config_for "$cli"
      ;;
    opencode)
      sync_agents_for "opencode"
      if [ "$CLAUDE_SKILLS_SYNCED" -eq 0 ]; then
        log "opencode lê skills nativamente de ~/.claude/skills (compat Claude Code) — sincronizando esse diretório mesmo sem o binário claude instalado"
        sync_skills_for "claude"
      fi
      configure_opencode_deepseek_default
      sync_global_config_for "opencode"
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
