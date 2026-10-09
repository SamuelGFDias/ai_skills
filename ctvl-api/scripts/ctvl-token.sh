#!/usr/bin/env bash
set -euo pipefail
CTVLCMD_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=lib-ctvl.sh
source "$CTVLCMD_DIR/lib-ctvl.sh"
# Garante um JWT admin válido em cache (modo 600) e informa a validade. NUNCA imprime o token.
# Uso: ctvl-token.sh <ambiente> [--refresh | --status]
#   (sem opção)  usa o cache se ainda válido, senão faz login (POST /api-token-auth/)
#   --refresh    força novo login      --status   só informa o cache, sem rede
# A credencial admin vem de <ambiente>.ADMIN_USER/ADMIN_PASSWORD no arquivo de credenciais
# (ou CTVL_ADMIN_PASSWORD_<APELIDO> no ambiente do processo). Fornecida pelo usuário; nunca no chat.
# O cache do JWT é preso ao host+usuário do apelido: se o arquivo de credenciais mudar, o token é descartado.
if [ "$#" -lt 1 ]; then
  sed -n '2,7p' "${BASH_SOURCE[0]}" >&2
  exit 2
fi
ctvl_load_env "$1"
mode="${2:-}"
tf="$CTVLAPI_CACHE_DIR/${CTVLAPI_ALIAS}.jwt"
case "$mode" in
  --status)
    if ctvl_cache_ok; then
      ttl="$(python3 -B "$CTVLAPI_CORE" jwt-ttl "$tf" 2>/dev/null || echo 0)"
      printf 'ambiente %s: token em cache, validade restante ~%s s (valor não exibido)\n' "$CTVLAPI_ALIAS" "$ttl"
    else
      printf 'ambiente %s: sem token em cache (ou emitido para outro host/usuário)\n' "$CTVLAPI_ALIAS"
    fi
    ;;
  --refresh)
    ctvl_ensure_token --refresh
    ;;
  '')
    ctvl_ensure_token
    ttl="$(python3 -B "$CTVLAPI_CORE" jwt-ttl "$CTVLAPI_TOKEN_FILE" 2>/dev/null || echo 0)"
    printf 'ambiente %s: token válido por ~%s s (cache modo 600; valor não exibido)\n' "$CTVLAPI_ALIAS" "$ttl"
    ;;
  *)
    ctvl_die "opção desconhecida: $mode"
    ;;
esac
