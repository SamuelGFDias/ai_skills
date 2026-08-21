#!/usr/bin/env bash
# Lista os groups do realm (nível raiz, com subgrupos aninhados).
# Uso: kc-list-groups.sh <credAlias>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-env.sh
source "$SCRIPT_DIR/lib-env.sh"

CRED_ALIAS="${1:?uso: kc-list-groups.sh <credAlias>}"
load_credential_env "$CRED_ALIAS"

TOKEN="$("$SCRIPT_DIR/kc-token.sh" "$CRED_ALIAS")"

curl -sf -X GET "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_REALM}/groups?briefRepresentation=false" \
  -H "Authorization: Bearer ${TOKEN}"
