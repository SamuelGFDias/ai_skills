#!/usr/bin/env bash
set -euo pipefail
CTVLCMD_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=lib-ctvl.sh
source "$CTVLCMD_DIR/lib-ctvl.sh"
# Aplica o plano no vault. Idempotente; exige --yes; nunca deleta nada.
# Uso: ctvl-apply.sh <ambiente> (--file cfg.yaml | --docs-dir DIR) --yes [--skip-blocked]
#        [--allow-breaking-update] [--key-map GRUPO=CHAVE] [--email-domain D] [--no-verify]
# Senhas de usuários novos vêm de variáveis de ambiente (password_ref: env:CTVL_<NOME>_PASSWORD), nunca do
# arquivo; a senha admin (CTVL_ADMIN_PASSWORD*) é removida do ambiente do motor e não pode ser usada ali.
if [ "$#" -lt 1 ] || [ "$1" = "--offline" ]; then
  sed -n '2,6p' "${BASH_SOURCE[0]}" >&2
  exit 2
fi
ctvl_dispatch "$1" apply "${@:2}"
