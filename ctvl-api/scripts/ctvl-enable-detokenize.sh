#!/usr/bin/env bash
set -euo pipefail
CTVLCMD_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=lib-ctvl.sh
source "$CTVLCMD_DIR/lib-ctvl.sh"
# Habilita o detokenize (canGet=true) de UM usuário mascarado: único caminho que escreve canGet=true para perfil
# mascarado (o apply nunca escreve). Sem --yes é dry-run. Falha fechado se alguma pré-condição não bater.
# Uso: ctvl-enable-detokenize.sh <ambiente> <usuario> (--file cfg.yaml | --docs-dir DIR) [--yes] [--sample VALOR_FABRICADO]
# As senhas do usuário e do usuário de tokenize vêm das variáveis CTVL_*_PASSWORD (password_ref) do seu shell.
if [ "$#" -lt 2 ] || [ "$1" = "--offline" ]; then
  sed -n '6,10p' "${BASH_SOURCE[0]}" >&2
  exit 2
fi
ctvl_dispatch "$1" enable-detokenize "${@:2}"
