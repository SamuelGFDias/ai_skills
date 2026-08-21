#!/usr/bin/env bash
# Cadastra ou edita um client Keycloak, associado a um realm já cadastrado
# (kc setup-realm). O realm é escolhido por menu — não precisa redigitar
# base URL/realm, já que eles vivem no cadastro do realm.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-env.sh
source "$SCRIPT_DIR/lib-env.sh"

mkdir -p "$CLIENTS_DIR"
chmod 700 "$SECRETS_ROOT" "$CLIENTS_DIR"

mapfile -t REALM_ALIASES < <(list_realm_aliases)
if [ "${#REALM_ALIASES[@]}" -eq 0 ]; then
  echo "Nenhum realm cadastrado ainda. Rode 'kc setup-realm' primeiro (uma vez por ambiente)." >&2
  exit 1
fi

echo "Selecione o realm deste client:" >&2
REALM_ALIAS=""
PS3="Realm> "
select opt in "${REALM_ALIASES[@]}"; do
  if [ -n "${opt:-}" ]; then
    REALM_ALIAS="$opt"
    break
  fi
  echo "Opção inválida, escolha um número da lista." >&2
done

echo >&2
CLIENT_ALIAS="$(read_required "Alias para este client (ex: realm-dev-meu-app): ")"
check_alias_not_used_elsewhere "$CLIENT_ALIAS" "$USERS_DIR" "user"
ENV_FILE="$CLIENTS_DIR/${CLIENT_ALIAS}.env"

KEYCLOAK_CLIENT_ID=""
KEYCLOAK_CLIENT_SECRET=""
EDITING=0
if [ -f "$ENV_FILE" ]; then
  EDITING=1
  load_env_file_safe "$ENV_FILE" KEYCLOAK_REALM_ALIAS KEYCLOAK_CLIENT_ID KEYCLOAK_CLIENT_SECRET
  echo "Client '${CLIENT_ALIAS}' já existe (realm atual: ${KEYCLOAK_REALM_ALIAS}) — Enter mantém o valor atual." >&2
fi

CLIENT_ID="$(read_required_default "Client ID" "$KEYCLOAK_CLIENT_ID")"

if [ "$EDITING" = "1" ] && [ -n "$KEYCLOAK_CLIENT_SECRET" ]; then
  echo "Client Secret atual: $(mask_bar "${#KEYCLOAK_CLIENT_SECRET}") (${#KEYCLOAK_CLIENT_SECRET} caracteres)" >&2
  echo "Cole/digite uma nova secret para substituir, ou Enter em branco para manter a atual." >&2
fi
TYPED_SECRET="$(read_secret_masked "Client Secret: ")"

if [ -z "$TYPED_SECRET" ] && [ "$EDITING" = "1" ] && [ -n "$KEYCLOAK_CLIENT_SECRET" ]; then
  CLIENT_SECRET="$KEYCLOAK_CLIENT_SECRET"
else
  CLIENT_SECRET="$TYPED_SECRET"
  [ -n "$CLIENT_SECRET" ] || { echo "Secret não pode ficar vazia." >&2; exit 1; }
fi

cat > "$ENV_FILE" <<EOF
KEYCLOAK_REALM_ALIAS=${REALM_ALIAS}
KEYCLOAK_CLIENT_ID=${CLIENT_ID}
KEYCLOAK_CLIENT_SECRET=${CLIENT_SECRET}
EOF
chmod 600 "$ENV_FILE"

echo
echo "Client salvo: $CLIENT_ALIAS"
echo "  Realm:         $REALM_ALIAS"
echo "  Client ID:     $CLIENT_ID"
echo "  Client Secret: $(mask_bar "${#CLIENT_SECRET}") (${#CLIENT_SECRET} caracteres — confira se bate com o que você colou)"
