#!/usr/bin/env bash
# Lista os clients do realm, apenas id interno + clientId + name (sem secret).
# Uso: kc-list-clients.sh <alias>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ALIAS="${1:?uso: kc-list-clients.sh <alias>}"
ENV_FILE="$HOME/.claude/secrets/keycloak/${ALIAS}.env"
[ -f "$ENV_FILE" ] || { echo "Credenciais não encontradas: $ENV_FILE" >&2; exit 1; }
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

TOKEN="$("$SCRIPT_DIR/kc-token.sh" "$ALIAS")"

# Filtra a resposta para remover o campo "secret" antes de deixar o
# resultado visível (o endpoint /clients retorna a secret em texto puro).
curl -sf -X GET "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_REALM}/clients" \
  -H "Authorization: Bearer ${TOKEN}" \
  | python3 -c "
import sys, json
clients = json.load(sys.stdin)
out = [{'id': c['id'], 'clientId': c.get('clientId'), 'name': c.get('name'), 'enabled': c.get('enabled')} for c in clients]
print(json.dumps(out, indent=2, ensure_ascii=False))
"
