#!/usr/bin/env bash
# Detalha um group: subgrupos, membros e role mappings (realm + client).
# Uso: kc-group-detail.sh <credAlias|realmAlias> <groupId> [realmDestino]
# 1º argumento: ver comentário em kc-list-clients.sh.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-env.sh
source "$SCRIPT_DIR/lib-env.sh"

ARG1="${1:?uso: kc-group-detail.sh <credAlias|realmAlias> <groupId> [realmDestino]}"
GROUP_ID="${2:?informe o id interno do group}"

resolve_target_credential "$ARG1" "${3:-}"

TOKEN="$("$SCRIPT_DIR/kc-token.sh" "$CRED_ALIAS")"
BASE="${KEYCLOAK_BASE_URL}/admin/realms/${TARGET_REALM}/groups/${GROUP_ID}"

CHILDREN="$(api_request GET "${BASE}/children" -H "Authorization: Bearer ${TOKEN}")" || exit 1
MEMBERS="$(api_request GET "${BASE}/members" -H "Authorization: Bearer ${TOKEN}")" || exit 1
REALM_ROLES="$(api_request GET "${BASE}/role-mappings/realm" -H "Authorization: Bearer ${TOKEN}")" || exit 1
CLIENT_ROLE_MAPPINGS="$(api_request GET "${BASE}/role-mappings" -H "Authorization: Bearer ${TOKEN}")" || exit 1

python3 -c "
import json, sys
children, members, realm_roles, all_mappings = [json.loads(a) for a in sys.argv[1:5]]
print(json.dumps({
    'subGroups': children,
    'members': [{'id': m.get('id'), 'username': m.get('username'), 'enabled': m.get('enabled')} for m in members],
    'realmRoleMappings': [r.get('name') for r in realm_roles],
    'clientRoleMappings': {
        client_name: [rr.get('name') for rr in client_data.get('mappings', [])]
        for client_name, client_data in all_mappings.get('clientMappings', {}).items()
    }
}, indent=2, ensure_ascii=False))
" "$CHILDREN" "$MEMBERS" "$REALM_ROLES" "$CLIENT_ROLE_MAPPINGS"
