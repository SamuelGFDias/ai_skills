#!/usr/bin/env bash
set -euo pipefail
CTVLCMD_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=lib-ctvl.sh
source "$CTVLCMD_DIR/lib-ctvl.sh"
# Verifica máscaras pela API de DADOS: tokeniza com o usuário de serviço e detokeniza com cada usuário.
# Uso: ctvl-verify-mask.sh <ambiente> --file cfg.yaml --sistema S --datatype D --sample VALOR_FABRICADO
#        [--tokengroup G --template T] [--tokenize-user U] [--show-values]
# As senhas de dados vêm de variáveis de ambiente (password_ref) já presentes no seu shell
# (ex.: carregadas pela skill vault-factory); nada é lido de arquivo nem impresso.
if [ "$#" -lt 1 ] || [ "$1" = "--offline" ]; then
  sed -n '2,6p' "${BASH_SOURCE[0]}" >&2
  exit 2
fi
ctvl_load_env "$1"
shift
# API de dados usa Basic por usuário: não precisa (nem usa) JWT admin.
ctvl_py_conn verify-mask "$@"
