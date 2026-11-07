#!/usr/bin/env bash
# Uso: login.sh [alias]
# Faz login com a credencial cadastrada via setup-login.sh (padrão de alias: "default").
# Nunca aceita usuário/senha em texto puro como argumento — só o alias da credencial.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-secrets.sh
source "$SCRIPT_DIR/lib-secrets.sh"

ALIAS="${1:-default}"
load_cronograma_credential "$ALIAS"

BASE_URL="https://cronograma.saude.rj.gov.br/api"
COOKIE_JAR="${CRONOGRAMA_COOKIE_JAR:-$HOME/.cache/cronograma-cookies.txt}"
mkdir -p "$(dirname "$COOKIE_JAR")"

BODY=$(python3 -c 'import json,sys; print(json.dumps({"username": sys.argv[1], "password": sys.argv[2]}))' "$CRONOGRAMA_USERNAME" "$CRONOGRAMA_PASSWORD")

RESPONSE=$(curl -s -w '\n%{http_code}' -c "$COOKIE_JAR" -X POST \
  "$BASE_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d "$BODY")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
  echo "Erro no login (HTTP $HTTP_CODE):" >&2
  echo "$RESPONSE_BODY" >&2
  exit 1
fi

echo "Login OK. Cookie salvo em $COOKIE_JAR" >&2
echo "$RESPONSE_BODY" | python3 -m json.tool
