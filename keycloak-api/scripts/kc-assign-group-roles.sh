#!/usr/bin/env bash
# Mapeia uma ou mais roles de um client a um group já existente, dentro do MESMO ambiente
# (sem origem/destino — diferente de kc-mirror-group-roles.sh). Idempotente: roles já
# mapeadas são reportadas e não duplicadas. Não cria a hierarquia do group — falha se o
# group não existir, porque aqui não há um ambiente de origem confiável que garanta que o
# group deveria existir.
# Uso: kc-assign-group-roles.sh <credAlias|realmAlias> <groupPath> <clientIdName> <roleName> [<roleName> ...]
#   groupPath ex: /MeuApp/Administrador
#   1º argumento: ver comentário em kc-list-clients.sh (aceita também um realmAlias — resolve
#   sozinho uma credencial de admin do master da mesma instância).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-env.sh
source "$SCRIPT_DIR/lib-env.sh"

ARG1="${1:?uso: kc-assign-group-roles.sh <credAlias|realmAlias> <groupPath> <clientIdName> <roleName> [<roleName> ...]}"
GROUP_PATH="${2:?informe o groupPath, ex: /MeuApp/Administrador}"
CLIENT_ID_NAME="${3:?informe o clientId, ex: meu-app}"
shift 3
ROLE_NAMES=("$@")

if [ "${#ROLE_NAMES[@]}" -eq 0 ]; then
  echo "informe ao menos um roleName." >&2
  exit 1
fi

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

CLIENTS_RESP="$(api_request GET "${KEYCLOAK_BASE_URL}/admin/realms/${TARGET_REALM}/clients?clientId=${CLIENT_ID_NAME}" \
  -H "Authorization: Bearer ${TOKEN}")" || exit 1
CLIENT_UUID="$(echo "$CLIENTS_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')")"

if [ -z "$CLIENT_UUID" ]; then
  echo "Client '${CLIENT_ID_NAME}' não encontrado no realm ${TARGET_REALM}." >&2
  exit 1
fi

CLEAN_PATH="${GROUP_PATH#/}"
GROUP_ID=""
if ! GROUP_ID="$(group_id_by_path "$CLEAN_PATH")"; then
  echo "ERRO: group '${GROUP_PATH}' não existe no realm ${TARGET_REALM}; crie-o antes (console admin do Keycloak ou hierarquia via outro fluxo)." >&2
  exit 1
fi

CLIENT_ROLES_RESP="$(api_request GET "${KEYCLOAK_BASE_URL}/admin/realms/${TARGET_REALM}/clients/${CLIENT_UUID}/roles" \
  -H "Authorization: Bearer ${TOKEN}")" || exit 1

# Valida que todas as roles pedidas existem no client — atômico: se qualquer uma faltar,
# aborta sem fazer nenhuma escrita (evita mapeamento parcial silencioso).
MISSING_ROLES=0
for role_name in "${ROLE_NAMES[@]}"; do
  found="$(echo "$CLIENT_ROLES_RESP" | python3 -c "
import sys, json
roles = json.load(sys.stdin)
name = sys.argv[1]
print('1' if any(r['name'] == name for r in roles) else '')
" "$role_name")"
  if [ -z "$found" ]; then
    echo "ERRO: role '${role_name}' não existe no client '${CLIENT_ID_NAME}'; crie antes com: kc create-client-role ${ARG1} ${CLIENT_ID_NAME} ${role_name}" >&2
    MISSING_ROLES=1
  fi
done
[ "$MISSING_ROLES" = "0" ] || exit 1

CURRENT_MAPPINGS_RESP="$(api_request GET "${KEYCLOAK_BASE_URL}/admin/realms/${TARGET_REALM}/groups/${GROUP_ID}/role-mappings/clients/${CLIENT_UUID}" \
  -H "Authorization: Bearer ${TOKEN}")" || exit 1

ALREADY_MAPPED=()
TO_MAP=()
for role_name in "${ROLE_NAMES[@]}"; do
  already="$(echo "$CURRENT_MAPPINGS_RESP" | python3 -c "
import sys, json
mappings = json.load(sys.stdin)
name = sys.argv[1]
print('1' if any(m['name'] == name for m in mappings) else '')
" "$role_name")"
  if [ -n "$already" ]; then
    ALREADY_MAPPED+=("$role_name")
  else
    TO_MAP+=("$role_name")
  fi
done

if [ "${#TO_MAP[@]}" -gt 0 ]; then
  TO_MAP_JOINED="$(printf '%s\n' "${TO_MAP[@]}")"
  PAYLOAD="$(python3 -c "
import json, sys
names = set(n for n in sys.argv[1].split(chr(10)) if n)
roles = json.loads(sys.argv[2])
print(json.dumps([r for r in roles if r['name'] in names]))
" "$TO_MAP_JOINED" "$CLIENT_ROLES_RESP")"
  api_request POST "${KEYCLOAK_BASE_URL}/admin/realms/${TARGET_REALM}/groups/${GROUP_ID}/role-mappings/clients/${CLIENT_UUID}" \
    -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" -d "$PAYLOAD" >/dev/null || exit 1
fi

for role_name in "${TO_MAP[@]}"; do
  echo "OK: role '${role_name}' mapeada ao group '${GROUP_PATH}' (${CRED_ALIAS}/${TARGET_REALM})"
done
for role_name in "${ALREADY_MAPPED[@]}"; do
  echo "JÁ MAPEADA: role '${role_name}' já estava no group '${GROUP_PATH}'"
done
