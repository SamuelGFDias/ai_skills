#!/usr/bin/env bash
# Cria uma role em um client.
# Uso: kc-create-client-role.sh <credAlias|realmAlias> <clientId> <roleName> [descricao]
# 1º argumento: ver comentário em kc-list-clients.sh (aceita também um realmAlias — resolve
# sozinho uma credencial de admin do master da mesma instância).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-env.sh
source "$SCRIPT_DIR/lib-env.sh"

ARG1="${1:?uso: kc-create-client-role.sh <credAlias|realmAlias> <clientId> <roleName> [descricao]}"
CLIENT_ID_NAME="${2:?informe o clientId, ex: meu-app}"
ROLE_NAME="${3:?informe o nome da role}"
ROLE_DESC="${4:-}"

resolve_target_credential "$ARG1"

TOKEN="$("$SCRIPT_DIR/kc-token.sh" "$CRED_ALIAS")"

CLIENTS_RESP="$(api_request GET "${KEYCLOAK_BASE_URL}/admin/realms/${TARGET_REALM}/clients?clientId=${CLIENT_ID_NAME}" \
  -H "Authorization: Bearer ${TOKEN}")" || exit 1
INTERNAL_ID="$(echo "$CLIENTS_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')")"

if [ -z "$INTERNAL_ID" ]; then
  echo "Client '${CLIENT_ID_NAME}' não encontrado no realm ${TARGET_REALM}." >&2
  exit 1
fi

BODY="$(python3 -c "import json,sys; print(json.dumps({'name': sys.argv[1], 'description': sys.argv[2]}))" "$ROLE_NAME" "$ROLE_DESC")"

RESP_FILE="$(mktemp)"
HTTP_STATUS="$(curl -s -o "$RESP_FILE" -w "%{http_code}" -X POST \
  "${KEYCLOAK_BASE_URL}/admin/realms/${TARGET_REALM}/clients/${INTERNAL_ID}/roles" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$BODY")"

if [ "$HTTP_STATUS" = "201" ]; then
  echo "OK: role '${ROLE_NAME}' criada em ${CRED_ALIAS}/${TARGET_REALM}/${CLIENT_ID_NAME}"
elif [ "$HTTP_STATUS" = "409" ]; then
  echo "JÁ EXISTE: role '${ROLE_NAME}' em ${CRED_ALIAS}/${TARGET_REALM}/${CLIENT_ID_NAME}"
else
  echo "ERRO (HTTP $HTTP_STATUS) ao criar '${ROLE_NAME}':" >&2
  cat "$RESP_FILE" >&2
  echo >&2
  rm -f "$RESP_FILE"
  exit 1
fi
rm -f "$RESP_FILE"
