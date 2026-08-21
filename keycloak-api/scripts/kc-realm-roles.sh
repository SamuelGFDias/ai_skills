#!/usr/bin/env bash
# Lista as roles de nível de realm.
# Uso: kc-realm-roles.sh <credAlias>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-env.sh
source "$SCRIPT_DIR/lib-env.sh"

CRED_ALIAS="${1:?uso: kc-realm-roles.sh <credAlias>}"
load_credential_env "$CRED_ALIAS"

TOKEN="$("$SCRIPT_DIR/kc-token.sh" "$CRED_ALIAS")"

curl -sf -X GET "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_REALM}/roles" \
  -H "Authorization: Bearer ${TOKEN}"
