#!/usr/bin/env bash
set -euo pipefail
CTVLCMD_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=lib-ctvl.sh
source "$CTVLCMD_DIR/lib-ctvl.sh"
# Mostra o PLANO (criar/atualizar/já existe/bloqueado) de um arquivo declarativo. Nunca escreve.
# Saída compacta por padrão; --verbose (ou CTVL_VERBOSE=1) mostra o texto completo de cada item.
# Uso: ctvl-plan.sh <ambiente|--offline> (--file cfg.yaml | --docs-dir docs/tokenizacao-ctvl)
#        [--empty-state | --state-dir DIR] [--key-map GRUPO=CHAVE] [--email-domain D] [--include-legacy]
#        [--accept-suggestions] [--allow-breaking-update] [--show-extra] [--check] [--verbose]
if [ "$#" -lt 1 ]; then
  sed -n '2,6p' "${BASH_SOURCE[0]}" >&2
  exit 2
fi
ctvl_dispatch "$1" plan "${@:2}"
