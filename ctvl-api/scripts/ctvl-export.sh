#!/usr/bin/env bash
set -euo pipefail
CTVLCMD_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=lib-ctvl.sh
source "$CTVLCMD_DIR/lib-ctvl.sh"
# Exporta a configuração atual para um YAML declarativo, determinístico e SEM segredos.
# Uso: ctvl-export.sh <ambiente|--offline> [--out ARQUIVO.yaml] [--file cfg.yaml] [--state-dir DIR]
# Só leitura. Lista branca de campos: ids, hashes, tokens e sessões nunca entram no arquivo.
if [ "$#" -lt 1 ]; then
  sed -n '2,4p' "${BASH_SOURCE[0]}" >&2
  exit 2
fi
ctvl_dispatch "$1" export "${@:2}"
