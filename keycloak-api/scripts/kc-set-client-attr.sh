#!/usr/bin/env bash
# Altera pontualmente atributos (chave/valor) de um client, com dry-run por padrão.
# Uso: kc-set-client-attr.sh <credAlias|realmAlias> <clientId> <atributo>=<valor> [<atributo>=<valor> ...] [--apply] [realmDestino]
#
# <atributo>=<valor> vazio ou <atributo>=@unset remove o atributo da representação do client.
# Sem --apply: só mostra uma tabela ATRIBUTO | ATUAL | NOVO com o que MUDARIA, sem gravar nada.
# Com --apply: pede confirmação [s/N] (a menos que KC_ASSUME_YES=1), faz PUT com a
# representação completa (todos os campos originais preservados, attributes mesclado), e
# depois faz um novo GET para confirmar (tabela com coluna APLICADO).
#
# 1º argumento pode ser um credAlias (ou o alias de um REALM cadastrado, resolvendo sozinho
# uma credencial de admin do 'master' — ver resolve_target_credential em lib-env.sh).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-env.sh
source "$SCRIPT_DIR/lib-env.sh"

usage() {
  echo "uso: kc-set-client-attr.sh <credAlias|realmAlias> <clientId> <atributo>=<valor> [<atributo>=<valor> ...] [--apply] [realmDestino]" >&2
}

ARG1="${1:?$(usage)}"
CLIENT_ID_NAME="${2:?$(usage)}"
shift 2

APPLY=0
ATTR_PAIRS=()
REALM_DESTINO=""

for a in "$@"; do
  case "$a" in
    --apply)
      APPLY=1
      ;;
    *=*)
      ATTR_PAIRS+=("$a")
      ;;
    *)
      if [ -n "$REALM_DESTINO" ]; then
        echo "Argumento inesperado: '$a' (realmDestino já informado como '$REALM_DESTINO')." >&2
        usage
        exit 1
      fi
      REALM_DESTINO="$a"
      ;;
  esac
done

if [ "${#ATTR_PAIRS[@]}" -eq 0 ]; then
  echo "Informe ao menos um <atributo>=<valor>." >&2
  usage
  exit 1
fi

# Valida nomes de atributo e separa nome/valor/remoção antes de tocar na API.
ATTR_NAMES=()
ATTR_VALUES=()
ATTR_REMOVE=()

for pair in "${ATTR_PAIRS[@]}"; do
  name="${pair%%=*}"
  value="${pair#*=}"
  if ! [[ "$name" =~ ^[a-z0-9._-]+$ ]]; then
    echo "Nome de atributo inválido: '${name}' (precisa casar com ^[a-z0-9._-]+\$)." >&2
    exit 1
  fi
  ATTR_NAMES+=("$name")
  if [ -z "$value" ] || [ "$value" = "@unset" ]; then
    ATTR_VALUES+=("")
    ATTR_REMOVE+=("1")
  else
    ATTR_VALUES+=("$value")
    ATTR_REMOVE+=("0")
  fi
done

resolve_target_credential "$ARG1" "$REALM_DESTINO"

TOKEN="$("$SCRIPT_DIR/kc-token.sh" "$CRED_ALIAS")"

CLIENTS_RESP="$(api_request GET "${KEYCLOAK_BASE_URL}/admin/realms/${TARGET_REALM}/clients?clientId=${CLIENT_ID_NAME}" \
  -H "Authorization: Bearer ${TOKEN}")" || exit 1

# Representação completa do client (inclui "secret" em texto puro) — fica só em variável de
# shell, nunca é impressa em stdout/stderr; só passa a jq para leitura/montagem de payload.
CLIENT_REPR="$(echo "$CLIENTS_RESP" | jq -c '.[0] // empty')"

if [ -z "$CLIENT_REPR" ]; then
  echo "Client '${CLIENT_ID_NAME}' não encontrado no realm ${TARGET_REALM}." >&2
  exit 1
fi

INTERNAL_ID="$(echo "$CLIENT_REPR" | jq -r '.id')"

# Lê o valor de um atributo em uma representação JSON do client, com fallback legível.
_attr_value_or_default() {
  local repr="$1" name="$2" fallback="$3" v
  v="$(echo "$repr" | jq -r --arg k "$name" '.attributes[$k] // "__MISSING__"')"
  [ "$v" = "__MISSING__" ] && v="$fallback"
  printf '%s' "$v"
}

# Dry-run: ATRIBUTO | ATUAL (valor hoje em $1) | NOVO (o que --apply gravaria).
print_table_dry_run() {
  local repr="$1"
  printf '%-35s | %-25s | %-25s\n' "ATRIBUTO" "ATUAL" "NOVO"
  local i name cur new
  for i in "${!ATTR_NAMES[@]}"; do
    name="${ATTR_NAMES[$i]}"
    cur="$(_attr_value_or_default "$repr" "$name" "(não definido)")"
    if [ "${ATTR_REMOVE[$i]}" = "1" ]; then
      new="(remover)"
    else
      new="${ATTR_VALUES[$i]}"
    fi
    printf '%-35s | %-25s | %-25s\n' "$name" "$cur" "$new"
  done
}

# Pós-aplicação: ATRIBUTO | ATUAL (valor antes, em $1) | APLICADO (valor real depois, em $2,
# lido de volta do Keycloak — não confia no payload enviado).
print_table_applied() {
  local before_repr="$1" after_repr="$2"
  printf '%-35s | %-25s | %-25s\n' "ATRIBUTO" "ATUAL" "APLICADO"
  local i name cur applied
  for i in "${!ATTR_NAMES[@]}"; do
    name="${ATTR_NAMES[$i]}"
    cur="$(_attr_value_or_default "$before_repr" "$name" "(não definido)")"
    applied="$(_attr_value_or_default "$after_repr" "$name" "(não definido)")"
    printf '%-35s | %-25s | %-25s\n' "$name" "$cur" "$applied"
  done
}

echo "Client '${CLIENT_ID_NAME}' no realm ${TARGET_REALM}:"
print_table_dry_run "$CLIENT_REPR"

if [ "$APPLY" -ne 1 ]; then
  echo
  echo "Nenhuma alteração aplicada. Use --apply para gravar."
  exit 0
fi

echo
if [ "${KC_ASSUME_YES:-}" != "1" ]; then
  CONFIRM=""
  read -rp "Confirma gravar essas alterações no client '${CLIENT_ID_NAME}' (${TARGET_REALM})? [s/N] " CONFIRM
  case "$CONFIRM" in
    [sS]|[sS][iI][mM]) ;;
    *)
      echo "Cancelado, nenhuma alteração aplicada." >&2
      exit 1
      ;;
  esac
fi

# Monta o novo objeto "attributes" mesclado: parte do que já existe, seta/remove só os
# atributos informados, e produz a representação completa (todos os demais campos originais
# preservados, incluindo "secret") para o PUT — o Keycloak substitui o recurso inteiro.
NEW_REPR="$CLIENT_REPR"
for i in "${!ATTR_NAMES[@]}"; do
  name="${ATTR_NAMES[$i]}"
  if [ "${ATTR_REMOVE[$i]}" = "1" ]; then
    NEW_REPR="$(echo "$NEW_REPR" | jq -c --arg k "$name" '.attributes = ((.attributes // {}) | del(.[$k]))')"
  else
    value="${ATTR_VALUES[$i]}"
    NEW_REPR="$(echo "$NEW_REPR" | jq -c --arg k "$name" --arg v "$value" '.attributes = ((.attributes // {}) + {($k): $v})')"
  fi
done

PUT_STATUS_FILE="$(mktemp)"
HTTP_STATUS="$(curl -s -o "$PUT_STATUS_FILE" -w '%{http_code}' -X PUT \
  "${KEYCLOAK_BASE_URL}/admin/realms/${TARGET_REALM}/clients/${INTERNAL_ID}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$NEW_REPR")"

if [ "$HTTP_STATUS" -lt 200 ] || [ "$HTTP_STATUS" -ge 300 ]; then
  echo "Erro HTTP ${HTTP_STATUS} ao gravar atributos de '${CLIENT_ID_NAME}':" >&2
  # A resposta de erro do PUT de /clients não costuma trazer "secret", mas por segurança
  # não ecoa o corpo bruto — só a mensagem, no mesmo padrão de api_request.
  python3 -c "
import json
try:
    with open('$PUT_STATUS_FILE') as f:
        data = json.load(f)
    if isinstance(data, dict):
        msg = data.get('errorMessage') or data.get('error_description') or data.get('error')
        if msg:
            print(msg)
except Exception:
    pass
" >&2
  rm -f "$PUT_STATUS_FILE"
  exit 1
fi
rm -f "$PUT_STATUS_FILE"

# Confirma lendo de novo do Keycloak (não confia só no payload que foi enviado).
CONFIRM_RESP="$(api_request GET "${KEYCLOAK_BASE_URL}/admin/realms/${TARGET_REALM}/clients/${INTERNAL_ID}" \
  -H "Authorization: Bearer ${TOKEN}")" || exit 1

echo
echo "Gravado. Estado atual em ${TARGET_REALM}/${CLIENT_ID_NAME}:"
print_table_applied "$CLIENT_REPR" "$CONFIRM_RESP"
