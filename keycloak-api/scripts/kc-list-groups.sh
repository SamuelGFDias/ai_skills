#!/usr/bin/env bash
# Lista os groups do realm (nível raiz, com subgrupos aninhados).
# Uso: kc-list-groups.sh <alias>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ALIAS="${1:?uso: kc-list-groups.sh <alias>}"
ENV_FILE="$HOME/.claude/secrets/keycloak/${ALIAS}.env"
[ -f "$ENV_FILE" ] || { echo "Credenciais não encontradas: $ENV_FILE" >&2; exit 1; }
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

TOKEN="$("$SCRIPT_DIR/kc-token.sh" "$ALIAS")"

curl -sf -X GET "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_REALM}/groups?briefRepresentation=false" \
  -H "Authorization: Bearer ${TOKEN}"
