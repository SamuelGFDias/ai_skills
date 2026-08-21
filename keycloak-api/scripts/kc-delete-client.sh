#!/usr/bin/env bash
# Remove um client cadastrado nesta skill (arquivo local em
# ~/.claude/secrets/keycloak/clients/). Nunca afeta o client no Keycloak em si — só o
# cadastro local usado por essa skill para autenticar.
# Uso: kc-delete-client.sh <alias>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-env.sh
source "$SCRIPT_DIR/lib-env.sh"

ALIAS="${1:?uso: kc-delete-client.sh <alias>}"
ENV_FILE="$CLIENTS_DIR/${ALIAS}.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Nenhum client cadastrado com o alias '${ALIAS}'." >&2
  exit 1
fi

KEYCLOAK_REALM_ALIAS=""
load_env_file_safe "$ENV_FILE" KEYCLOAK_REALM_ALIAS

CONFIRM=""
read -rp "Remover o client '${ALIAS}' (realm: ${KEYCLOAK_REALM_ALIAS})? Isso apaga só o arquivo local, não afeta o client no Keycloak. [s/N] " CONFIRM
case "$CONFIRM" in
  [sS]|[sS][iI][mM])
    rm -f "$ENV_FILE"
    echo "Removido: ${ALIAS}"
    ;;
  *)
    echo "Cancelado." >&2
    exit 1
    ;;
esac
