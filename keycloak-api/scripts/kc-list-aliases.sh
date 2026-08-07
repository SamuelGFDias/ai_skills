#!/usr/bin/env bash
# Lista os aliases de credenciais Keycloak já cadastrados em
# ~/.claude/secrets/keycloak/*.env — mostra alias, base URL, realm e
# client ID (nunca o client_secret).
set -euo pipefail

SECRETS_DIR="$HOME/.claude/secrets/keycloak"

if [ ! -d "$SECRETS_DIR" ] || [ -z "$(ls -A "$SECRETS_DIR" 2>/dev/null)" ]; then
  echo "Nenhum alias cadastrado ainda. Rode: kc setup-credentials" >&2
  exit 0
fi

printf '%-25s %-45s %-20s %-15s\n' "ALIAS" "BASE_URL" "REALM" "CLIENT_ID"

for env_file in "$SECRETS_DIR"/*.env; do
  [ -e "$env_file" ] || continue
  alias_name="$(basename "$env_file" .env)"

  KEYCLOAK_BASE_URL=""
  KEYCLOAK_REALM=""
  KEYCLOAK_CLIENT_ID=""
  # shellcheck disable=SC1090
  source <(grep -E '^KEYCLOAK_(BASE_URL|REALM|CLIENT_ID)=' "$env_file")

  printf '%-25s %-45s %-20s %-15s\n' \
    "$alias_name" "$KEYCLOAK_BASE_URL" "$KEYCLOAK_REALM" "$KEYCLOAK_CLIENT_ID"
done
