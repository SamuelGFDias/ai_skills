#!/usr/bin/env bash
# Lista as roles de um client específico pelo clientId (nome, ex: "biae").
# Uso: kc-client-roles.sh <alias> <clientId>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ALIAS="${1:?uso: kc-client-roles.sh <alias> <clientId>}"
CLIENT_ID_NAME="${2:?informe o clientId, ex: biae}"
ENV_FILE="$HOME/.claude/secrets/keycloak/${ALIAS}.env"
[ -f "$ENV_FILE" ] || { echo "Credenciais não encontradas: $ENV_FILE" >&2; exit 1; }
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

TOKEN="$("$SCRIPT_DIR/kc-token.sh" "$ALIAS")"

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
