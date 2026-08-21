#!/usr/bin/env bash
# Lista as credenciais de usuário cadastradas localmente (alias, realm associado,
# client id de login, username — sem senha).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-env.sh
source "$SCRIPT_DIR/lib-env.sh"

if [ ! -d "$USERS_DIR" ] || [ -z "$(ls -A "$USERS_DIR" 2>/dev/null)" ]; then
  echo "Nenhum usuário cadastrado ainda. Rode: kc setup-user" >&2
  exit 0
fi

printf '%-25s %-20s %-15s %-20s\n' "USER_ALIAS" "REALM_ALIAS" "CLIENT_ID" "USERNAME"

for env_file in "$USERS_DIR"/*.env; do
  [ -e "$env_file" ] || continue
  user_alias="$(basename "$env_file" .env)"

  load_env_file_safe "$env_file" KEYCLOAK_REALM_ALIAS KEYCLOAK_CLIENT_ID KEYCLOAK_USERNAME

  printf '%-25s %-20s %-15s %-20s\n' "$user_alias" "$KEYCLOAK_REALM_ALIAS" "$KEYCLOAK_CLIENT_ID" "$KEYCLOAK_USERNAME"
done
