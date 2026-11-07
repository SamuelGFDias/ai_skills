#!/usr/bin/env bash
set -euo pipefail
CTVLCMD_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=lib-ctvl.sh
source "$CTVLCMD_DIR/lib-ctvl.sh"
# Lista a configuração ATUAL do vault em tabela (padrão), YAML ou JSON.
# Uso: ctvl-list.sh <ambiente|--offline> <recurso> [--format table|yaml|json] [--file cfg.yaml] [--state-dir DIR]
#   recurso: masks | users | groups | tokengroups | templates | charsets | keys | formats | permissions | all
# Só leitura (GET). Usuários mostram a máscara e o grupo; nomes fora da convenção são sinalizados.
if [ "$#" -lt 2 ]; then
  sed -n '2,5p' "${BASH_SOURCE[0]}" >&2
  exit 2
fi
ctvl_dispatch "$1" list "${@:2}"
