#!/usr/bin/env bash
# Obtém um access_token para a credencial informada (client_credentials ou password,
# conforme o tipo resolvido por load_credential_env).
# Uso: kc-token.sh <credAlias>
# Imprime o token em stdout (uso interno por outros scripts via $(...)).
# Não deve ser usado diretamente para exibir o token na conversa.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-env.sh
source "$SCRIPT_DIR/lib-env.sh"

CRED_ALIAS="${1:?uso: kc-token.sh <credAlias>}"
load_credential_env "$CRED_ALIAS"

case "$KEYCLOAK_AUTH_TYPE" in
  client_credentials)
    curl -sf -X POST "${KEYCLOAK_BASE_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "grant_type=client_credentials" \
      -d "client_id=${KEYCLOAK_CLIENT_ID}" \
      -d "client_secret=${KEYCLOAK_CLIENT_SECRET}" \
      | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])"
    ;;
  password)
    curl -sf -X POST "${KEYCLOAK_BASE_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "grant_type=password" \
      -d "client_id=${KEYCLOAK_CLIENT_ID}" \
      -d "username=${KEYCLOAK_USERNAME}" \
      -d "password=${KEYCLOAK_PASSWORD}" \
      | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])"
    ;;
  *)
    echo "Tipo de credencial desconhecido para '${CRED_ALIAS}': ${KEYCLOAK_AUTH_TYPE}" >&2
    exit 1
    ;;
esac
