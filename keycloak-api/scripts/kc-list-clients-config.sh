#!/usr/bin/env bash
# Lista os clients cadastrados localmente (alias, realm associado, client id — sem secret).
# Não confundir com "kc list-clients <clientAlias>", que consulta a API do Keycloak.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-env.sh
source "$SCRIPT_DIR/lib-env.sh"

if [ ! -d "$CLIENTS_DIR" ] || [ -z "$(ls -A "$CLIENTS_DIR" 2>/dev/null)" ]; then
  echo "Nenhum client cadastrado ainda. Rode: kc setup-client" >&2
  exit 0
fi

printf '%-25s %-20s %-20s\n' "CLIENT_ALIAS" "REALM_ALIAS" "CLIENT_ID"

for env_file in "$CLIENTS_DIR"/*.env; do
  [ -e "$env_file" ] || continue
  client_alias="$(basename "$env_file" .env)"

  load_env_file_safe "$env_file" KEYCLOAK_REALM_ALIAS KEYCLOAK_CLIENT_ID

  printf '%-25s %-20s %-20s\n' "$client_alias" "$KEYCLOAK_REALM_ALIAS" "$KEYCLOAK_CLIENT_ID"
done
