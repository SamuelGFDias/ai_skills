#!/usr/bin/env bash
# Lista os realms disponíveis: cadastro local do usuário + os versionados da equipe
# (keycloak-api/realms/), indicando a origem de cada um. Quando um alias existe nos dois,
# o local prevalece (mesma regra usada por load_credential_env) e é o que aparece aqui.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-env.sh
source "$SCRIPT_DIR/lib-env.sh"

mapfile -t ALIASES < <(list_realm_aliases)
if [ "${#ALIASES[@]}" -eq 0 ]; then
  echo "Nenhum realm disponível (nem local, nem da equipe). Rode: kc setup-realm" >&2
  exit 0
fi

printf '%-20s %-45s %-20s %-8s\n' "REALM_ALIAS" "BASE_URL" "REALM" "ORIGEM"

for alias in "${ALIASES[@]}"; do
  env_file="$(resolve_realm_env_file "$alias")"
  origin="$(realm_origin "$alias")"

  load_env_file_safe "$env_file" KEYCLOAK_BASE_URL KEYCLOAK_REALM

  printf '%-20s %-45s %-20s %-8s\n' "$alias" "$KEYCLOAK_BASE_URL" "$KEYCLOAK_REALM" "$origin"
done
