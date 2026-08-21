#!/usr/bin/env bash
# Espelha, de uma credencial/realm de origem para um de destino, os client-role-mappings
# de um group (por path). Cria o group no destino se não existir. Idempotente.
# Uso: kc-mirror-group-roles.sh <sourceCredAlias> <targetCredAlias> <groupPath> <clientIdName> [--recursive]
#   groupPath ex: /MeuApp/Administrador
#   --recursive: aplica também a todos os subgrupos (por nome) da origem
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-env.sh
source "$SCRIPT_DIR/lib-env.sh"

RECURSIVE=0
ARGS=()
for a in "$@"; do
  if [ "$a" = "--recursive" ]; then RECURSIVE=1; else ARGS+=("$a"); fi
done
set -- "${ARGS[@]}"

SRC_ALIAS="${1:?uso: kc-mirror-group-roles.sh <sourceCredAlias> <targetCredAlias> <groupPath> <clientIdName> [--recursive]}"
TGT_ALIAS="${2:?}"
GROUP_PATH="${3:?}"
CLIENT_NAME="${4:?}"

load_credential_env "$SRC_ALIAS"
SRC_BASE="$KEYCLOAK_BASE_URL"
SRC_REALM="$KEYCLOAK_REALM"

load_credential_env "$TGT_ALIAS"
TGT_BASE="$KEYCLOAK_BASE_URL"
TGT_REALM="$KEYCLOAK_REALM"

SRC_TOKEN="$("$SCRIPT_DIR/kc-token.sh" "$SRC_ALIAS")"
TGT_TOKEN="$("$SCRIPT_DIR/kc-token.sh" "$TGT_ALIAS")"

url_encode_path() {
  python3 -c "import urllib.parse,sys; print('/'.join(urllib.parse.quote(s) for s in sys.argv[1].split('/')))" "$1"
}

client_uuid() { # base realm token clientName
  curl -sf -H "Authorization: Bearer $3" "$1/admin/realms/$2/clients?clientId=$4" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')"
}

SRC_CLIENT_UUID="$(client_uuid "$SRC_BASE" "$SRC_REALM" "$SRC_TOKEN" "$CLIENT_NAME")"
TGT_CLIENT_UUID="$(client_uuid "$TGT_BASE" "$TGT_REALM" "$TGT_TOKEN" "$CLIENT_NAME")"
[ -n "$SRC_CLIENT_UUID" ] || { echo "client '$CLIENT_NAME' não encontrado na origem" >&2; exit 1; }
[ -n "$TGT_CLIENT_UUID" ] || { echo "client '$CLIENT_NAME' não encontrado no destino" >&2; exit 1; }

group_id_by_path() { # base realm token cleanPath -> imprime id, ou nada + retorna 1 se 404
  local base="$1" realm="$2" token="$3" clean="$4"
  local enc body status
  enc="$(url_encode_path "$clean")"
  body="$(mktemp)"
  status="$(curl -s -o "$body" -w "%{http_code}" -H "Authorization: Bearer $token" "$base/admin/realms/$realm/group-by-path/$enc")"
  if [ "$status" = "200" ]; then
    python3 -c "import json; print(json.load(open('$body'))['id'])"
  fi
  rm -f "$body"
  [ "$status" = "200" ]
}

ensure_group_path() { # base realm token cleanPath -> cria hierarquia faltante, imprime id final
  local base="$1" realm="$2" token="$3" path="$4"
  local parent_id="" accum=""
  IFS='/' read -ra segs <<< "$path"
  for seg in "${segs[@]}"; do
    [ -z "$seg" ] && continue
    accum="${accum:+$accum/}$seg"
    local id
    if id="$(group_id_by_path "$base" "$realm" "$token" "$accum")"; then
      parent_id="$id"
    else
      local create_url
      if [ -z "$parent_id" ]; then
        create_url="$base/admin/realms/$realm/groups"
      else
        create_url="$base/admin/realms/$realm/groups/$parent_id/children"
      fi
      local hdrs status loc
      hdrs="$(mktemp)"
      status="$(curl -s -o /dev/null -D "$hdrs" -w '%{http_code}' -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
        -d "{\"name\":\"$seg\"}" "$create_url")"
      loc="$(tr -d '\r' < "$hdrs" | grep -i '^location:' | awk '{print $2}')"
      rm -f "$hdrs"
      if [ -z "$loc" ]; then
        echo "erro: falha ao criar segmento de group '$seg' (path acumulado: '$accum') em '$create_url' — resposta HTTP $status sem header Location; abortando para evitar corromper a hierarquia de groups no destino" >&2
        exit 1
      fi
      parent_id="${loc##*/}"
    fi
  done
  echo "$parent_id"
}

group_role_names() { # base realm token groupId clientUuid
  curl -sf -H "Authorization: Bearer $3" "$1/admin/realms/$2/groups/$4/role-mappings/clients/$5" \
    | python3 -c "import sys,json; print(chr(10).join(r['name'] for r in json.load(sys.stdin)))"
}

do_group() {
  local path="$1"
  local clean="${path#/}"

  local src_group_id
  if ! src_group_id="$(group_id_by_path "$SRC_BASE" "$SRC_REALM" "$SRC_TOKEN" "$clean")"; then
    echo "  [pular] '$path' não existe na origem"
    return
  fi

  local tgt_group_id
  tgt_group_id="$(ensure_group_path "$TGT_BASE" "$TGT_REALM" "$TGT_TOKEN" "$clean")"

  local src_names tgt_names missing
  src_names="$(group_role_names "$SRC_BASE" "$SRC_REALM" "$SRC_TOKEN" "$src_group_id" "$SRC_CLIENT_UUID" | grep -v '^$' | sort -u || true)"
  tgt_names="$(group_role_names "$TGT_BASE" "$TGT_REALM" "$TGT_TOKEN" "$tgt_group_id" "$TGT_CLIENT_UUID" | grep -v '^$' | sort -u || true)"
  missing="$(comm -23 <(echo "$src_names") <(echo "$tgt_names") 2>/dev/null | grep -v '^$' || true)"

  if [ -z "$missing" ]; then
    local n
    n="$(echo "$src_names" | grep -c . || true)"
    echo "  '$path': já em paridade ($n roles)"
  else
    local tgt_roles_full payload n_missing
    tgt_roles_full="$(curl -sf -H "Authorization: Bearer $TGT_TOKEN" "$TGT_BASE/admin/realms/$TGT_REALM/clients/$TGT_CLIENT_UUID/roles")"
    payload="$(python3 -c "
import json, sys
names = set(n for n in sys.argv[1].split(chr(10)) if n)
roles = json.loads(sys.argv[2])
print(json.dumps([r for r in roles if r['name'] in names]))
" "$missing" "$tgt_roles_full")"
    curl -sf -X POST -H "Authorization: Bearer $TGT_TOKEN" -H "Content-Type: application/json" \
      -d "$payload" "$TGT_BASE/admin/realms/$TGT_REALM/groups/$tgt_group_id/role-mappings/clients/$TGT_CLIENT_UUID" >/dev/null
    n_missing="$(echo "$missing" | grep -c .)"
    echo "  '$path': +$n_missing role(s) adicionada(s)"
  fi

  if [ "$RECURSIVE" = "1" ]; then
    local children
    children="$(curl -sf -H "Authorization: Bearer $SRC_TOKEN" "$SRC_BASE/admin/realms/$SRC_REALM/groups/$src_group_id/children" \
      | python3 -c "import sys,json; print(chr(10).join(c['name'] for c in json.load(sys.stdin)))")"
    while IFS= read -r child; do
      [ -z "$child" ] && continue
      do_group "$path/$child"
    done <<< "$children"
  fi
}

echo "Espelhando group role-mappings do client '${CLIENT_NAME}': ${SRC_ALIAS} -> ${TGT_ALIAS}"
do_group "$GROUP_PATH"
