#!/usr/bin/env bash
# Lista as roles de um client específico pelo clientId (nome, ex: "biae").
# Uso: kc-client-roles.sh <credAlias> <clientId>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-env.sh
source "$SCRIPT_DIR/lib-env.sh"

CRED_ALIAS="${1:?uso: kc-client-roles.sh <credAlias> <clientId>}"
CLIENT_ID_NAME="${2:?informe o clientId, ex: biae}"
load_credential_env "$CRED_ALIAS"

TOKEN="$("$SCRIPT_DIR/kc-token.sh" "$CRED_ALIAS")"

# Resolve o id interno do client SEM expor o corpo completo da resposta
# (que inclui o campo "secret" em texto puro) — extrai só o id via jq/python.
INTERNAL_ID="$(curl -sf -X GET "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_REALM}/clients?clientId=${CLIENT_ID_NAME}" \
  -H "Authorization: Bearer ${TOKEN}" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')")"

if [ -z "$INTERNAL_ID" ]; then
  echo "Client '${CLIENT_ID_NAME}' não encontrado no realm ${KEYCLOAK_REALM}." >&2
  exit 1
fi

curl -sf -X GET "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_REALM}/clients/${INTERNAL_ID}/roles" \
  -H "Authorization: Bearer ${TOKEN}"
