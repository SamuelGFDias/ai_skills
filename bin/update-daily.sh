#!/usr/bin/env bash
# update-daily.sh — rotina do repo de skills: `git pull --ff-only` em todos os remotes e, quando
# algo realmente mudou, um `bin/install.sh` para propagar skills/subagentes/instruções globais para
# os CLIs desta máquina. Escreve um log por execução.
#
# Por que o sync condicional importa: em Linux/WSL o claude/codex/gemini leem a skill por symlink,
# então o pull já basta; mas no Windows (Git Bash) o destino é cópia, e skill nova/removida só
# aparece com sync. Além disso o sync-global-config.sh precisa ser reavaliado quando uma skill nova
# ganha global.md. Rodar o install.sh a cada pull (mesmo sem mudança) só gastaria tempo.
#
# Seguro para rodar sem terminal (cron):
#   - nunca pergunta nada: o install.sh só pergunta quando há snippet global sem escolha salva;
#     nesse caso ele próprio não altera nada (e o log registra o aviso);
#   - nunca commita, nunca faz merge/rebase automático: `pull --ff-only` falha se o histórico
#     divergir (commit local ou alteração não commitada em conflito) — o log registra e o script
#     sai com código 1 sem tocar no working tree;
#   - não roda nenhum CLI de IA. O install.sh só cria symlinks/cópias e configs.
#
# Log: ${AI_SKILLS_LOG_DIR:-$HOME/.local/state/ai-skills}/update-daily.log
#   Toda a saída da execução vai para o arquivo (append), com cabeçalho e rodapé de status.
#   Rotação por tamanho: passando de AI_SKILLS_LOG_MAX_BYTES (1 MiB), vira update-daily.log.1
#   (uma geração).
#
# Uso:
#   bin/update-daily.sh                          # update + sync se mudou
#   bin/update-daily.sh --dry-run                # mostra o que faria (fetch + diff, sem pull/sync)
#   bin/update-daily.sh --no-sync                # só atualiza o repo, nunca roda install.sh
#   bin/update-daily.sh --repo <dir>             # outro clone (default: pai deste script)
#   bin/update-daily.sh --status                 # último log + entrada de crontab + estado do repo
#   bin/update-daily.sh --install [--dry-run]    # instala/atualiza a entrada de crontab
#   bin/update-daily.sh --uninstall [--dry-run]  # remove a entrada de crontab
#
# Configuração (variáveis de ambiente; também aceitas como flags no --install):
#   AI_SKILLS_UPDATE_TIME       hora do cron, HH:MM          (--time)      default 09:00
#   AI_SKILLS_UPDATE_DAYS       dias do cron (0=dom..6=sáb)  (--days)      default * (todos)
#   AI_SKILLS_UPDATE_SYNC       1/0: roda install.sh ao mudar (--no-sync)  default 1
#   AI_SKILLS_LOG_DIR           pasta do log                               default ~/.local/state/ai-skills
#   AI_SKILLS_LOG_MAX_BYTES     limite de rotação do log                   default 1048576
#   AI_SKILLS_UPDATE_NICEIONICE 1/0: chamar com `nice -n 10 ionice -c3`    default 1
#
# A entrada de crontab gerada é sempre única e marcada com um comentário
# (`# ai-skills update-daily`); reinstalar troca a entrada existente, nunca duplica. O cron roda
# sem login shell: o comando é montado com `cd` + `bash` usando o caminho absoluto deste script,
# e a saída é redirecionada para o mesmo log — por isso o comportamento via cron é idêntico ao
# manual. No Windows/Git Bash não há crontab: use o Agendador de Tarefas com
# `bash bin/update-daily.sh` (ver o bloco "Rotina diária" no AGENTS.md).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR_DEFAULT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="${AI_SKILLS_LOG_DIR:-$HOME/.local/state/ai-skills}"
LOG_FILE="$LOG_DIR/update-daily.log"
LOG_MAX_BYTES="${AI_SKILLS_LOG_MAX_BYTES:-1048576}"
CRON_MARK="# ai-skills update-daily"

REPO_DIR="$REPO_DIR_DEFAULT"
MODE="apply"          # apply | dry-run
ACTION="update"       # update | status | install | uninstall

# Parâmetros da rotina (flags sobrepõem as variáveis de ambiente).
TIME_SPEC="${AI_SKILLS_UPDATE_TIME:-09:00}"
DAYS_SPEC="${AI_SKILLS_UPDATE_DAYS:-*}"
SYNC_SPEC="${AI_SKILLS_UPDATE_SYNC:-1}"
NICE_SPEC="${AI_SKILLS_UPDATE_NICEIONICE:-1}"

usage() { sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) MODE="dry-run" ;;
    --no-sync) SYNC_SPEC=0 ;;
    --repo) shift; REPO_DIR="${1:?--repo exige um diretório}" ;;
    --time) shift; TIME_SPEC="${1:?--time exige HH:MM}" ;;
    --days) shift; DAYS_SPEC="${1:?--days exige 0-6 (ex.: 1-5 ou *)}" ;;
    --status) ACTION="status" ;;
    --install) ACTION="install" ;;
    --uninstall) ACTION="uninstall" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "argumento desconhecido: $1 (--help)" >&2; exit 2 ;;
  esac
  shift
done

log() { echo ">> $*"; }
die() { echo "ERRO: $*" >&2; exit 2; }

# O cron não herda LANG/LC_ALL: sem isso o git e o install.sh respondem em inglês, e o log fica
# misturando idiomas conforme quem rodou. Fixar o locale do log em UTF-8.
export LANG="${AI_SKILLS_UPDATE_LANG:-pt_BR.UTF-8}"
export LC_ALL="${AI_SKILLS_UPDATE_LANG:-pt_BR.UTF-8}"

# ---------- validação dos parâmetros ----------

# HH:MM -> "minuto hora" (os dois primeiros campos do cron). Só imprime; quem chama valida
# (`validate_params`) antes — um `die` dentro de `$(...)` morreria no subshell e o cron sairia
# malformado.
cron_time() {
  local h="${1%:*}" m="${1#*:}"
  echo "$((10#$m)) $((10#$h))"
}

validate_time() {
  [[ "$1" =~ ^([01]?[0-9]|2[0-3]):([0-5][0-9])$ ]] || die "hora inválida: '$1' (use HH:MM, 00:00-23:59)"
}

# * | 0-6 | lista/ranges separados por vírgula (ex.: 1-5, 1,3,5) -> campo de cron
validate_days() {
  local d="$1" part
  [ "$d" = "*" ] && return 0
  [ -n "$d" ] || die "dias inválidos: vazio (use * ou 0-6)"
  # Checar o formato inteiro antes do split: `IFS=, read -a` colapsa separadores vazios, então
  # "1-5," ou ",1" passariam como se fossem válidos.
  [[ "$d" =~ ^[0-6](,[0-6])*$ || "$d" =~ ^[0-6]-[0-6](,[0-6](-[0-6])?)*$ ]] \
    || die "dias inválidos: '$d' (use * ou combinação de 0-6, ex.: 1-5, 1,3,5)"
  IFS=',' read -r -a parts <<< "$d"
  for part in "${parts[@]}"; do
    if [[ "$part" =~ ^([0-6])-([0-6])$ ]] && [ "${BASH_REMATCH[1]}" -gt "${BASH_REMATCH[2]}" ]; then
      die "dias inválidos: '$d' (range invertido em '$part')"
    fi
  done
}

validate_params() {
  validate_time "$TIME_SPEC"
  validate_days "$DAYS_SPEC"
  [ "$SYNC_SPEC" = "1" ] || [ "$SYNC_SPEC" = "0" ] || die "sync inválido: '$SYNC_SPEC' (use 1 ou 0)"
  [ "$NICE_SPEC" = "1" ] || [ "$NICE_SPEC" = "0" ] || die "nice/ionice inválido: '$NICE_SPEC' (use 1 ou 0)"
}

cron_body() {
  local script="$1" sync="$2" nice="$3"
  local cmd="cd $(printf '%q' "$REPO_DIR") && bash $(printf '%q' "$script")"
  [ "$sync" = "0" ] && cmd+=" --no-sync"
  [ "$nice" = "1" ] && cmd="nice -n 10 ionice -c3 $cmd"
  echo "$cmd"
}

cron_line() {
  local time="$1" days="$2" script="$3" sync="$4" nice="$5"
  # Cron tem 5 campos: minuto hora dia-do-mês mês dia-da-semana. `--days` controla só o dia da
  # semana; dia-do-mês e mês ficam em "*". Concatenar campo a campo deixa explícito quantos existem.
  local line
  line="$(cron_time "$time") * * $days "
  line+="$(cron_body "$script" "$sync" "$nice") "
  line+="$CRON_MARK"
  echo "$line"
}

SCRIPT_PATH="$REPO_DIR/bin/update-daily.sh"

# ---------- status ----------

current_cron_line() { crontab -l 2>/dev/null | grep -F "$CRON_MARK" || true; }

if [ "$ACTION" = "status" ]; then
  validate_params
  echo "Log: $LOG_FILE"
  if [ -f "$LOG_FILE" ]; then
    echo "----- últimas execuções -----"
    tail -n 40 "$LOG_FILE"
  else
    echo "(nenhuma execução registrada ainda)"
  fi
  echo
  echo "----- rotina instalada (crontab) -----"
  if current_cron_line | grep -q .; then
    current_cron_line
    echo
    echo "agendamento esperado agora seria:"
    cron_line "$TIME_SPEC" "$DAYS_SPEC" "$SCRIPT_PATH" "$SYNC_SPEC" "$NICE_SPEC"
  else
    echo "(nenhuma entrada — rode: bin/update-daily.sh --install)"
  fi
  echo
  echo "----- repo -----"
  git -C "$REPO_DIR" status --short --branch || true
  exit 0
fi

# ---------- install / uninstall (só crontab) ----------

if [ "$ACTION" = "install" ] || [ "$ACTION" = "uninstall" ]; then
  validate_params
  command -v crontab >/dev/null 2>&1 || die "crontab não encontrado. No Windows/Git Bash use o Agendador de Tarefas com 'bash $SCRIPT_PATH'."

  if [ "$ACTION" = "install" ]; then
    [ -f "$SCRIPT_PATH" ] || die "$SCRIPT_PATH não existe"
    chmod +x "$SCRIPT_PATH" 2>/dev/null || true
  fi

  LINE="$(cron_line "$TIME_SPEC" "$DAYS_SPEC" "$SCRIPT_PATH" "$SYNC_SPEC" "$NICE_SPEC")"
  EXISTING="$(crontab -l 2>/dev/null || true)"
  # Remove qualquer entrada antiga da rotina (por marcador ou pelo próprio script), preservando
  # o resto do crontab do usuário. As duas formas cobrem entradas antigas com outro formato.
  KEEP="$(printf '%s\n' "$EXISTING" | grep -vF "$CRON_MARK" | grep -vF "$SCRIPT_PATH" || true)"

  if [ "$ACTION" = "install" ]; then
    log "rotina: $LINE"
    if [ "$MODE" = "dry-run" ]; then
      log "(dry-run) crontab resultante seria:"
      { [ -n "$KEEP" ] && printf '%s\n' "$KEEP"; printf '%s\n' "$LINE"; } | sed 's/^/    /'
      exit 0
    fi
    { [ -n "$KEEP" ] && printf '%s\n' "$KEEP"; printf '%s\n' "$LINE"; } | crontab -
    log "crontab atualizado (entrada única, marcada com '$CRON_MARK')"
    log "confira: crontab -l   |   bin/update-daily.sh --status"
    exit 0
  fi

  if ! current_cron_line | grep -q .; then
    log "nenhuma entrada da rotina no crontab — nada a remover"
    exit 0
  fi
  if [ "$MODE" = "dry-run" ]; then
    log "(dry-run) removeria do crontab:"
    current_cron_line | sed 's/^/    /'
    exit 0
  fi
  { [ -n "$KEEP" ] && printf '%s\n' "$KEEP"; } | crontab -
  log "crontab: entrada da rotina removida"
  exit 0
fi

# ---------- update (caminho normal; é o que o cron executa) ----------

[ -d "$REPO_DIR/.git" ] || die "$REPO_DIR não é um repositório git"
mkdir -p "$LOG_DIR"

# Rotação: uma geração.
if [ -f "$LOG_FILE" ]; then
  size="$(wc -c < "$LOG_FILE" | tr -d ' ')"
  if [ "$size" -gt "$LOG_MAX_BYTES" ]; then
    mv -f "$LOG_FILE" "$LOG_FILE.1"
  fi
fi

# Saída -> log (append). No terminal, também ecoa. O cron, quando chamado pela entrada gerada,
# já redireciona para este mesmo arquivo; o redirecionamento aqui garante o mesmo log quando
# alguém roda à mão, sem `tee` (que pode não existir em cron mínimo).
if [ -t 1 ]; then
  exec > >(tee -a "$LOG_FILE") 2>&1
else
  exec >> "$LOG_FILE" 2>&1
fi

STARTED_AT="$(date '+%Y-%m-%d %H:%M:%S %z')"
echo
echo "=================================================================="
echo "[$STARTED_AT] update-daily ($MODE) repo=$REPO_DIR sync=$SYNC_SPEC"

cleanup_footer() {
  local code=$?
  local status
  status=$([ "$code" -eq 0 ] && echo "ok" || echo "FALHOU (exit $code)")
  echo "[$(date '+%Y-%m-%d %H:%M:%S %z')] fim: $status"
  exit "$code"
}
trap cleanup_footer EXIT

cd "$REPO_DIR"

# Remotes com refspec de fetch (origin, gitlab, ...). Remote só de push não tem o que puxar.
REMOTES=()
while IFS= read -r r; do
  [ -n "$r" ] && REMOTES+=("$r")
done < <(git config --get-regexp '^remote\..*\.fetch$' | sed 's/^remote\.\(.*\)\.fetch.*/\1/')

if [ "${#REMOTES[@]}" -eq 0 ]; then
  log "nenhum remote com fetch configurado — não há o que atualizar"
  exit 0
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$BRANCH" = "HEAD" ]; then
  log "ERRO: HEAD destacado (detached); ajuste para uma branch antes de usar a rotina"
  exit 1
fi

CHANGED_REMOTE=""
ANY_FAIL=0
SUMMARY=()
PREV_HEAD="$(git rev-parse HEAD)"

if [ -n "$(git status --porcelain)" ]; then
  log "AVISO: working tree tem alterações locais; pull --ff-only vai abortar se elas conflitarem com o remoto"
fi

# Um único fetch antes do loop evita baixar tudo de novo em cada remote.
if [ "$MODE" = "dry-run" ]; then
  log "git fetch --all --prune --dry-run"
  git fetch --all --prune --dry-run
else
  log "git fetch --all --prune"
  if ! git fetch --all --prune; then
    log "ERRO: fetch falhou (rede? credencial?). Nada foi alterado."
    exit 1
  fi
fi

for r in "${REMOTES[@]}"; do
  remote_ref="refs/remotes/$r/$BRANCH"
  if ! git rev-parse --verify --quiet "$remote_ref" >/dev/null; then
    SUMMARY+=("$r: branch '$BRANCH' não existe nesse remote — ignorado")
    continue
  fi

  if [ "$MODE" = "dry-run" ]; then
    read -r ahead behind < <(git rev-list --left-right --count "HEAD...$remote_ref")
    SUMMARY+=("$r: local está ${ahead:-0} à frente, ${behind:-0} atrás de $remote_ref (dry-run, sem pull)")
    [ "${behind:-0}" -gt 0 ] && CHANGED_REMOTE="$r"
    continue
  fi

  log "git pull --ff-only $r $BRANCH"
  if git pull --ff-only "$r" "$BRANCH"; then
    AFTER="$(git rev-parse HEAD)"
    if [ "$PREV_HEAD" != "$AFTER" ]; then
      CHANGED_REMOTE="$r"
      SUMMARY+=("$r: atualizado ${PREV_HEAD:0:8}..${AFTER:0:8}")
      PREV_HEAD="$AFTER"
    else
      SUMMARY+=("$r: já estava em dia")
    fi
  else
    ANY_FAIL=$((ANY_FAIL + 1))
    SUMMARY+=("$r: falhou (histórico divergente ou alteração local em conflito) — resolva manualmente e rode de novo")
  fi
done

log "resumo por remote:"
for line in "${SUMMARY[@]}"; do log "  $line"; done

if [ "$ANY_FAIL" -gt 0 ]; then
  log "ERRO: $ANY_FAIL remote(s) falharam; install.sh NÃO será executado"
  exit 1
fi

if [ -z "$CHANGED_REMOTE" ]; then
  log "hook: nada novo — install.sh não é necessário (symlinks e configs já refletem o repo)"
elif [ "$SYNC_SPEC" = "0" ]; then
  log "hook: mudou ($CHANGED_REMOTE), mas o sync está desligado (--no-sync / AI_SKILLS_UPDATE_SYNC=0)"
elif [ ! -x "$REPO_DIR/bin/install.sh" ]; then
  log "ERRO: bin/install.sh ausente ou sem bit de execução; rode manualmente"
  exit 1
else
  log "hook: mudou ($CHANGED_REMOTE) — rodando bin/install.sh"
  if [ "$MODE" = "dry-run" ]; then
    "$REPO_DIR/bin/install.sh" --dry-run
    log "install.sh executado em dry-run (nenhuma alteração feita)"
  else
    "$REPO_DIR/bin/install.sh"
  fi
fi

log "concluído"
