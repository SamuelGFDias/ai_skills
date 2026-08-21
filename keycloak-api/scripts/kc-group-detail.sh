#!/usr/bin/env bash
# Detalha um group: subgrupos, membros e role mappings (realm + client).
# Uso: kc-group-detail.sh <credAlias> <groupId>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-env.sh
source "$SCRIPT_DIR/lib-env.sh"

CRED_ALIAS="${1:?uso: kc-group-detail.sh <credAlias> <groupId>}"
GROUP_ID="${2:?informe o id interno do group}"

load_credential_env "$CRED_ALIAS"

TOKEN="$("$SCRIPT_DIR/kc-token.sh" "$CRED_ALIAS")"
BASE="${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_REALM}/groups/${GROUP_ID}"

CHILDREN="$(curl -sf -H "Authorization: Bearer ${TOKEN}" "${BASE}/children")"
MEMBERS="$(curl -sf -H "Authorization: Bearer ${TOKEN}" "${BASE}/members")"
REALM_ROLES="$(curl -sf -H "Authorization: Bearer ${TOKEN}" "${BASE}/role-mappings/realm")"
CLIENT_ROLE_MAPPINGS="$(curl -sf -H "Authorization: Bearer ${TOKEN}" "${BASE}/role-mappings")"

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
