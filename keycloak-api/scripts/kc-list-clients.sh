#!/usr/bin/env bash
# Lista os clients do realm, apenas id interno + clientId + name (sem secret).
# Uso: kc-list-clients.sh <credAlias|realmAlias> [realmDestino]
# 1º argumento pode ser um credAlias (comportamento explícito de sempre; realmDestino
# opcional sobrescreve o realm consultado) OU o alias de um REALM cadastrado — nesse caso
# resolve sozinho uma credencial de admin do 'master' da mesma instância (ver
# resolve_target_credential em lib-env.sh).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-env.sh
source "$SCRIPT_DIR/lib-env.sh"

ARG1="${1:?uso: kc-list-clients.sh <credAlias|realmAlias> [realmDestino]}"
resolve_target_credential "$ARG1" "${2:-}"

TOKEN="$("$SCRIPT_DIR/kc-token.sh" "$CRED_ALIAS")"

# Filtra a resposta para remover o campo "secret" antes de deixar o
# resultado visível (o endpoint /clients retorna a secret em texto puro).
BODY="$(api_request GET "${KEYCLOAK_BASE_URL}/admin/realms/${TARGET_REALM}/clients" \
  -H "Authorization: Bearer ${TOKEN}")" || exit 1
echo "$BODY" | python3 -c "
import sys, json
clients = json.load(sys.stdin)
out = [{'id': c['id'], 'clientId': c.get('clientId'), 'name': c.get('name'), 'enabled': c.get('enabled')} for c in clients]
print(json.dumps(out, indent=2, ensure_ascii=False))
"
