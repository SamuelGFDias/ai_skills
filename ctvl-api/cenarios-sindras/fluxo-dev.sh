#!/usr/bin/env bash
# Wrapper fino sobre o CLI `ctvl` para o fluxo DEV da tokenização (feature 004). Só ambiente dev.
# Nunca imprime senha/token; nunca remove nada; escrita só com --yes explícito.
set -euo pipefail

AQUI="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"   # pasta do kit (na skill), nunca a do projeto
AMB="dev"
RUNNER="$AQUI/cenarios.py"

# Raiz do checkout do Sindras: SINDRAS_ROOT ou git rev-parse --show-toplevel a partir do cwd.
achar_raiz() {
  local r="${SINDRAS_ROOT:-}"
  [[ -n "$r" ]] || r="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  printf '%s' "$r"
}
RAIZ="$(achar_raiz)"
if [[ -n "$RAIZ" ]]; then export SINDRAS_ROOT="$RAIZ"; fi
CONFIG="${CTVL_CONFIG:-${RAIZ:+$RAIZ/docs/tokenizacao-ctvl/config-sindras-dev.yaml}}"
MASCARADOS=(sindras_cpf_3_left_2_right sindras_cpf_0_left_2_right sindras_cns_3_left sindras_cns_0_left_0_right)
VARS_SENHA=(CTVL_SINDRAS_SVC_TOKENIZE_PASSWORD CTVL_SINDRAS_TOTAL_PASSWORD CTVL_SINDRAS_CPF_3_LEFT_2_RIGHT_PASSWORD
  CTVL_SINDRAS_CPF_0_LEFT_2_RIGHT_PASSWORD CTVL_SINDRAS_CNS_3_LEFT_PASSWORD CTVL_SINDRAS_CNS_0_LEFT_0_RIGHT_PASSWORD)

uso() {
  cat <<'USO'
Uso: fluxo-dev.sh [--config ARQ] <subcomando> [args]      (ambiente fixo: dev)
  status                       plano atual (ctvl plan) + usuários do cofre (ctvl list users)
  plan                         ctvl plan com a config do Sindras
  apply [--yes]                sem --yes só mostra o plano; com --yes aplica (ctvl apply --yes)
  verificar                    ctvl verify-mask por datatype (cpf, cns) com amostra sintética
  habilitar <usuario> [--yes]  ctvl enable-detokenize (sem --yes é dry-run); usuário mascarado
  cenarios [args]              roda cenarios.py (do kit) (ex.: --cenario todos, --offline, --so-leitura)
Env: SINDRAS_ROOT (raiz do checkout do Sindras; padrão git toplevel do cwd), SINDRAS_ENV (padrão ~/dev/sindras/sindras.env), CTVL_CONFIG ou --config (padrão docs/tokenizacao-ctvl/config-sindras-dev.yaml)
Ordem: plan -> apply --yes -> verificar -> habilitar <u> --yes (um por vez) -> cenarios --cenario todos
USO
}

die() { echo "erro: $*" >&2; exit 1; }

exigir_ctvl() {
  command -v ctvl >/dev/null 2>&1 || die "ctvl não está no PATH"
  [[ -n "$CONFIG" ]] || die "raiz do Sindras não encontrada: rode a partir do checkout do Sindras ou exporte SINDRAS_ROOT (ou use CTVL_CONFIG)"
  [[ -r "$CONFIG" ]] || die "config não encontrada: $CONFIG"
}

carregar_env() {
  local f="${SINDRAS_ENV:-$HOME/dev/sindras/sindras.env}"
  [[ -r "$f" ]] || die "arquivo env não encontrado ($f); defina SINDRAS_ENV"
  set -a
  # shellcheck source=/dev/null
  source "$f"
  set +a
}

exigir_senhas() {
  carregar_env
  local v faltando=()
  for v in "${VARS_SENHA[@]}"; do
    if [[ -z "${!v:-}" ]]; then faltando+=("$v"); fi
  done
  if ((${#faltando[@]} > 0)); then die "variáveis de senha ausentes no env: ${faltando[*]}"; fi
}

amostra() {  # amostra sintética válida do datatype (cpf|cns), gerada por lib.py
  python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import lib; print(getattr(lib, "gerar_" + sys.argv[2])(900))' \
    "$AQUI" "$1"
}

cmd_status() {
  exigir_ctvl
  ctvl plan "$AMB" --file "$CONFIG"
  ctvl list "$AMB" users
}

cmd_plan() {
  exigir_ctvl
  ctvl plan "$AMB" --file "$CONFIG" "$@"
}

cmd_apply() {
  local yes=0 a
  for a in "$@"; do
    case "$a" in
      --yes) yes=1 ;;
      *) die "apply: argumento desconhecido '$a' (só --yes)" ;;
    esac
  done
  exigir_ctvl
  if ((yes == 1)); then
    exigir_senhas
    ctvl apply "$AMB" --file "$CONFIG" --yes
  else
    ctvl plan "$AMB" --file "$CONFIG"
    echo "(sem --yes: apenas o plano; nada foi aplicado. Para aplicar: fluxo-dev.sh apply --yes)"
  fi
}

cmd_verificar() {
  exigir_ctvl
  exigir_senhas
  local dt
  for dt in cpf cns; do
    echo "== verify-mask $dt"
    ctvl verify-mask "$AMB" --file "$CONFIG" --sistema sindras --datatype "$dt" --sample "$(amostra "$dt")"
  done
}

cmd_habilitar() {
  local usuario="${1:-}" yes=0 dt valido=0 u
  [[ -n "$usuario" ]] || die "habilitar: informe o usuário (${MASCARADOS[*]})"
  shift
  if (($# > 0)); then
    if [[ "$1" == "--yes" && $# -eq 1 ]]; then yes=1; else die "habilitar: argumento desconhecido (só --yes)"; fi
  fi
  for u in "${MASCARADOS[@]}"; do
    if [[ "$u" == "$usuario" ]]; then valido=1; fi
  done
  ((valido == 1)) || die "habilitar: '$usuario' não é um usuário mascarado (${MASCARADOS[*]})"
  exigir_ctvl
  exigir_senhas
  dt="${usuario#sindras_}"
  dt="${dt%%_*}"
  if ((yes == 1)); then
    ctvl enable-detokenize "$AMB" "$usuario" --file "$CONFIG" --sample "$(amostra "$dt")" --yes
  else
    ctvl enable-detokenize "$AMB" "$usuario" --file "$CONFIG" --sample "$(amostra "$dt")"
    echo "(dry-run: nada foi escrito. Para habilitar: fluxo-dev.sh habilitar $usuario --yes)"
  fi
}

cmd_cenarios() {
  command -v python3 >/dev/null 2>&1 || die "python3 não está no PATH"
  local a offline=0
  for a in "$@"; do
    if [[ "$a" == "--offline" ]]; then offline=1; fi
  done
  if ((offline == 0)); then exigir_senhas; fi
  python3 "$RUNNER" "$@"
}

main() {
  if [[ "${1:-}" == "--config" ]]; then
    [[ -n "${2:-}" ]] || die "--config exige um caminho"
    CONFIG="$2"
    shift 2
  fi
  if (($# == 0)); then uso; return 1; fi
  local sub="$1"
  shift
  case "$sub" in
    status) cmd_status "$@" ;;
    plan) cmd_plan "$@" ;;
    apply) cmd_apply "$@" ;;
    verificar) cmd_verificar "$@" ;;
    habilitar) cmd_habilitar "$@" ;;
    cenarios) cmd_cenarios "$@" ;;
    -h | --help | help) uso ;;
    *) uso >&2; die "subcomando desconhecido: $sub" ;;
  esac
}

main "$@"
