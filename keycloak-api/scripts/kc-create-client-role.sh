#!/usr/bin/env bash
# Cria uma role em um client.
# Uso: kc-create-client-role.sh <alias> <clientId> <roleName> [descricao]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ALIAS="${1:?uso: kc-create-client-role.sh <alias> <clientId> <roleName> [descricao]}"
CLIENT_ID_NAME="${2:?informe o clientId, ex: biae}"
ROLE_NAME="${3:?informe o nome da role}"
ROLE_DESC="${4:-}"

ENV_FILE="$HOME/.claude/secrets/keycloak/${ALIAS}.env"
[ -f "$ENV_FILE" ] || { echo "Credenciais não encontradas: $ENV_FILE" >&2; exit 1; }
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

TOKEN="$("$SCRIPT_DIR/kc-token.sh" "$ALIAS")"

INTERNAL_ID="$(curl -sf -X GET "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_REALM}/clients?clientId=${CLIENT_ID_NAME}" \
  -H "Authorization: Bearer ${TOKEN}" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')")"

if [ -z "$INTERNAL_ID" ]; then
  echo "Client '${CLIENT_ID_NAME}' não encontrado no realm ${KEYCLOAK_REALM}." >&2
  exit 1
fi

BODY="$(python3 -c "import json,sys; print(json.dumps({'name': sys.argv[1], 'description': sys.argv[2]}))" "$ROLE_NAME" "$ROLE_DESC")"

HTTP_STATUS="$(curl -s -o /tmp/kc-create-role-resp.$$ -w "%{http_code}" -X POST \
  "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_REALM}/clients/${INTERNAL_ID}/roles" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$BODY")"

if [ "$HTTP_STATUS" = "201" ]; then
  echo "OK: role '${ROLE_NAME}' criada em ${ALIAS}/${CLIENT_ID_NAME}"
elif [ "$HTTP_STATUS" = "409" ]; then
  echo "JÁ EXISTE: role '${ROLE_NAME}' em ${ALIAS}/${CLIENT_ID_NAME}"
else
  echo "ERRO (HTTP $HTTP_STATUS) ao criar '${ROLE_NAME}':" >&2
  cat "/tmp/kc-create-role-resp.$$" >&2
  echo >&2
  rm -f "/tmp/kc-create-role-resp.$$"
  exit 1
fi
rm -f "/tmp/kc-create-role-resp.$$"
