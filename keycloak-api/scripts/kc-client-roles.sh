#!/usr/bin/env bash
# Lista as roles de um client específico pelo clientId (nome, ex: "meu-app").
# Uso: kc-client-roles.sh <credAlias|realmAlias> <clientId> [realmDestino]
# 1º argumento: ver comentário em kc-list-clients.sh.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-env.sh
source "$SCRIPT_DIR/lib-env.sh"

ARG1="${1:?uso: kc-client-roles.sh <credAlias|realmAlias> <clientId> [realmDestino]}"
CLIENT_ID_NAME="${2:?informe o clientId, ex: meu-app}"
resolve_target_credential "$ARG1" "${3:-}"

TOKEN="$("$SCRIPT_DIR/kc-token.sh" "$CRED_ALIAS")"

# Resolve o id interno do client SEM expor o corpo completo da resposta
# (que inclui o campo "secret" em texto puro) — extrai só o id via jq/python.
BODY="$(api_request GET "${KEYCLOAK_BASE_URL}/admin/realms/${TARGET_REALM}/clients?clientId=${CLIENT_ID_NAME}" \
  -H "Authorization: Bearer ${TOKEN}")" || exit 1
INTERNAL_ID="$(echo "$BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')")"

if [ -z "$INTERNAL_ID" ]; then
  echo "Client '${CLIENT_ID_NAME}' não encontrado no realm ${TARGET_REALM}." >&2
  exit 1
fi

api_request GET "${KEYCLOAK_BASE_URL}/admin/realms/${TARGET_REALM}/clients/${INTERNAL_ID}/roles" \
  -H "Authorization: Bearer ${TOKEN}"
