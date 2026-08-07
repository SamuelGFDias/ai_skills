#!/usr/bin/env bash
# Obtém um access_token via client_credentials para o alias informado.
# Uso: kc-token.sh <alias>
# Imprime o token em stdout (uso interno por outros scripts via $(...)).
# Não deve ser usado diretamente para exibir o token na conversa.
set -euo pipefail

ALIAS="${1:?uso: kc-token.sh <alias>}"
ENV_FILE="$HOME/.claude/secrets/keycloak/${ALIAS}.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Credenciais não encontradas para o alias '${ALIAS}': $ENV_FILE" >&2
  echo "Rode setup-credentials.sh primeiro." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

curl -sf -X POST "${KEYCLOAK_BASE_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=${KEYCLOAK_CLIENT_ID}" \
  -d "client_secret=${KEYCLOAK_CLIENT_SECRET}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])"
