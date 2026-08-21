#!/usr/bin/env bash
# Cadastra ou edita uma credencial de usuário (username/senha via grant_type=password),
# associada a um realm já cadastrado (kc setup-realm). Use isso para operações fora do
# escopo de um client — ex: quando não há service account habilitado e a chamada precisa
# ser feita como um usuário humano/admin do realm.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-env.sh
source "$SCRIPT_DIR/lib-env.sh"

mkdir -p "$USERS_DIR"
chmod 700 "$SECRETS_ROOT" "$USERS_DIR"

mapfile -t REALM_ALIASES < <(list_realm_aliases)
if [ "${#REALM_ALIASES[@]}" -eq 0 ]; then
  echo "Nenhum realm cadastrado ainda. Rode 'kc setup-realm' primeiro (uma vez por ambiente)." >&2
  exit 1
fi

echo "Selecione o realm deste usuário:" >&2
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
USER_ALIAS="$(read_required "Alias para esta credencial de usuário (ex: sesrj-dev-admin): ")"
check_alias_not_used_elsewhere "$USER_ALIAS" "$CLIENTS_DIR" "client"
ENV_FILE="$USERS_DIR/${USER_ALIAS}.env"

KEYCLOAK_CLIENT_ID=""
KEYCLOAK_USERNAME=""
KEYCLOAK_PASSWORD=""
EDITING=0
if [ -f "$ENV_FILE" ]; then
  EDITING=1
  load_env_file_safe "$ENV_FILE" KEYCLOAK_REALM_ALIAS KEYCLOAK_CLIENT_ID KEYCLOAK_USERNAME KEYCLOAK_PASSWORD
  echo "Usuário '${USER_ALIAS}' já existe (realm atual: ${KEYCLOAK_REALM_ALIAS}) — Enter mantém o valor atual." >&2
fi

# admin-cli é o client público padrão do Keycloak para grant_type=password; raramente
# precisa mudar, mas fica editável para ambientes com client próprio para login humano.
CLIENT_ID="$(read_required_default "Client ID usado no login (grant_type=password)" "${KEYCLOAK_CLIENT_ID:-admin-cli}")"
USERNAME="$(read_required_default "Username" "$KEYCLOAK_USERNAME")"

if [ "$EDITING" = "1" ] && [ -n "$KEYCLOAK_PASSWORD" ]; then
  echo "Senha atual: $(mask_bar "${#KEYCLOAK_PASSWORD}") (${#KEYCLOAK_PASSWORD} caracteres)" >&2
  echo "Cole/digite uma nova senha para substituir, ou Enter em branco para manter a atual." >&2
fi
TYPED_PASSWORD="$(read_secret_masked "Password: ")"

if [ -z "$TYPED_PASSWORD" ] && [ "$EDITING" = "1" ] && [ -n "$KEYCLOAK_PASSWORD" ]; then
  PASSWORD="$KEYCLOAK_PASSWORD"
else
  PASSWORD="$TYPED_PASSWORD"
  [ -n "$PASSWORD" ] || { echo "Password não pode ficar em branco." >&2; exit 1; }
fi

cat > "$ENV_FILE" <<EOF
KEYCLOAK_REALM_ALIAS=${REALM_ALIAS}
KEYCLOAK_CLIENT_ID=${CLIENT_ID}
KEYCLOAK_USERNAME=${USERNAME}
KEYCLOAK_PASSWORD=${PASSWORD}
EOF
chmod 600 "$ENV_FILE"

echo
echo "Usuário salvo: $USER_ALIAS"
echo "  Realm:      $REALM_ALIAS"
echo "  Client ID:  $CLIENT_ID"
echo "  Username:   $USERNAME"
echo "  Password:   $(mask_bar "${#PASSWORD}") (${#PASSWORD} caracteres — confira se bate com o que você colou)"
