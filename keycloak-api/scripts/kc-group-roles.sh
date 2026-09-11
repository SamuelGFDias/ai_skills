#!/usr/bin/env bash
# Lista de forma simples as roles mapeadas (realm + client) de um group/subgroup, resolvido
# por PATH (não id) — alternativa mais legível a kc-group-detail.sh quando só se quer ver as
# roles (sem members nem subgrupos), sem precisar descobrir o groupId antes.
# Uso: kc-group-roles.sh <credAlias|realmAlias> <groupPath> [clientIdName]
#   groupPath ex: /MeuApp/Administrador
#   clientIdName (opcional): filtra a saída só pras roles desse client.
#   1º argumento: ver comentário em kc-list-clients.sh (aceita também um realmAlias — resolve
#   sozinho uma credencial de admin do master da mesma instância).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-env.sh
source "$SCRIPT_DIR/lib-env.sh"

ARG1="${1:?uso: kc-group-roles.sh <credAlias|realmAlias> <groupPath> [clientIdName]}"
GROUP_PATH="${2:?informe o groupPath, ex: /MeuApp/Administrador}"
CLIENT_ID_NAME="${3:-}"

resolve_target_credential "$ARG1"

TOKEN="$("$SCRIPT_DIR/kc-token.sh" "$CRED_ALIAS")"

url_encode_path() {
  python3 -c "import urllib.parse,sys; print('/'.join(urllib.parse.quote(s) for s in sys.argv[1].split('/')))" "$1"
}

group_id_by_path() { # cleanPath -> imprime id, ou nada + retorna 1 se 404
  local clean="$1"
  local enc body status
  enc="$(url_encode_path "$clean")"
  body="$(mktemp)"
  status="$(curl -s -o "$body" -w "%{http_code}" -H "Authorization: Bearer $TOKEN" "$KEYCLOAK_BASE_URL/admin/realms/$TARGET_REALM/group-by-path/$enc")"
  if [ "$status" = "200" ]; then
    python3 -c "import json; print(json.load(open('$body'))['id'])"
  fi
  rm -f "$body"
  [ "$status" = "200" ]
}

CLEAN_PATH="${GROUP_PATH#/}"
GROUP_ID=""
if ! GROUP_ID="$(group_id_by_path "$CLEAN_PATH")"; then
  echo "ERRO: group '${GROUP_PATH}' não existe no realm ${TARGET_REALM}." >&2
  exit 1
fi

ROLE_MAPPINGS="$(api_request GET "${KEYCLOAK_BASE_URL}/admin/realms/${TARGET_REALM}/groups/${GROUP_ID}/role-mappings" \
  -H "Authorization: Bearer ${TOKEN}")" || exit 1

python3 -c "
import json, sys
mappings = json.loads(sys.argv[1])
group_path = sys.argv[2]
client_filter = sys.argv[3]

realm_roles = sorted(r.get('name') for r in mappings.get('realmMappings', []))
client_mappings = mappings.get('clientMappings', {}) or {}

if client_filter:
    client_data = client_mappings.get(client_filter)
    role_names = sorted(rr.get('name') for rr in (client_data.get('mappings', []) if client_data else []))
    print(f\"Roles de '{client_filter}' no group '{group_path}':\")
    if role_names:
        for name in role_names:
            print(f'  - {name}')
    else:
        print('  (nenhuma)')
else:
    print(f'Group: {group_path}')
    print()
    print('Realm roles:')
    if realm_roles:
        for name in realm_roles:
            print(f'  - {name}')
    else:
        print('  (nenhuma)')
    print()
    if client_mappings:
        print('Client roles:')
        for client_name in sorted(client_mappings.keys()):
            role_names = sorted(rr.get('name') for rr in client_mappings[client_name].get('mappings', []))
            print(f'  {client_name}:')
            for name in role_names:
                print(f'    - {name}')
    else:
        print('Client roles: (nenhuma)')
" "$ROLE_MAPPINGS" "$GROUP_PATH" "$CLIENT_ID_NAME"
