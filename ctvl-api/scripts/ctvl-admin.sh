#!/usr/bin/env bash
set -euo pipefail
CTVLCMD_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=lib-ctvl.sh
source "$CTVLCMD_DIR/lib-ctvl.sh"
# Cliente genérico da API admin do CT-VL. Mascara segredos, JWT, IPs e host na saída.
# Uso: ctvl-admin.sh <ambiente> <MÉTODO> <path> [--body-file F | --body-stdin | --body JSON]
#                    [--query chave=valor ...] [--all] [--yes]
#   GET sem --yes; POST/PUT/PATCH/DELETE EXIGEM --yes e sempre mostram o que vão fazer antes.
#   Corpo com senha: só --body-file (modo 600) ou --body-stdin; --body inline é recusado se tiver senha.
#   Ex.: ctvl-admin.sh dev GET /masks/ --all
#        ctvl-admin.sh dev POST /masks/ --body '{"name":"cns_3_left","showleft":3,"showright":0,"maskchar":"*"}' --yes
if [ "$#" -lt 3 ]; then
  sed -n '2,10p' "${BASH_SOURCE[0]}" >&2
  exit 2
fi
alias_="$1"
shift
args=()
stdin_tmp=""
trap '[ -z "$stdin_tmp" ] || rm -f "$stdin_tmp"' EXIT
while [ "$#" -gt 0 ]; do
  case "$1" in
    --body-stdin)
      # lê o corpo uma única vez para um arquivo 600 (permite repetir após renovar o token)
      stdin_tmp="$(mktemp)"
      cat >"$stdin_tmp"
      args+=(--body-file "$stdin_tmp")
      shift
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done
ctvl_dispatch "$alias_" request "${args[@]}"
