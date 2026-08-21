#!/usr/bin/env bash
# Lista as roles de nível de realm.
# Uso: kc-realm-roles.sh <credAlias|realmAlias> [realmDestino]
# 1º argumento: ver comentário em kc-list-clients.sh.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-env.sh
source "$SCRIPT_DIR/lib-env.sh"

ARG1="${1:?uso: kc-realm-roles.sh <credAlias|realmAlias> [realmDestino]}"
resolve_target_credential "$ARG1" "${2:-}"

TOKEN="$("$SCRIPT_DIR/kc-token.sh" "$CRED_ALIAS")"

api_request GET "${KEYCLOAK_BASE_URL}/admin/realms/${TARGET_REALM}/roles" \
  -H "Authorization: Bearer ${TOKEN}"
