#!/usr/bin/env bash
set -euo pipefail
CTVLCMD_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=lib-ctvl.sh
source "$CTVLCMD_DIR/lib-ctvl.sh"
# Lê o vault e mostra, por campo-referência, se a API devolve NOME ou ID (evidência), sem imprimir valores.
# Uso: ctvl-probe-refs.sh <ambiente|--offline> [--file cfg.yaml] [--state-dir DIR]
if [ "$#" -lt 1 ]; then
  sed -n '2,3p' "${BASH_SOURCE[0]}" >&2
  exit 2
fi
ctvl_dispatch "$1" probe-refs "${@:2}"
