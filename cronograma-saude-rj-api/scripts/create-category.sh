#!/usr/bin/env bash
# Uso: create-category.sh <projectId> <name>
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Uso: create-category.sh <projectId> <name>" >&2
  exit 1
fi

PROJECT_ID="$1"
NAME="$2"

if [[ -z "$PROJECT_ID" ]]; then
  echo "Erro: projectId não pode ser vazio." >&2
  exit 1
fi
if [[ -z "$NAME" ]]; then
  echo "Erro: name não pode ser vazio." >&2
  exit 1
fi

BASE_URL="https://cronograma.saude.rj.gov.br/api"
COOKIE_JAR="${CRONOGRAMA_COOKIE_JAR:-$HOME/.cache/cronograma-cookies.txt}"
mkdir -p "$(dirname "$COOKIE_JAR")"

BODY=$(python3 -c 'import json,sys; print(json.dumps({"name": sys.argv[1], "projectId": sys.argv[2]}))' "$NAME" "$PROJECT_ID")

echo "Enviando POST /api/categories com body: $BODY" >&2

RESPONSE=$(curl -s -w '\n%{http_code}' -b "$COOKIE_JAR" -X POST \
  "$BASE_URL/categories" \
  -H "Content-Type: application/json" \
  -d "$BODY")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
  echo "Erro ao criar categoria (HTTP $HTTP_CODE):" >&2
  echo "$RESPONSE_BODY" >&2
  exit 1
fi

echo "Categoria criada com sucesso:" >&2
echo "$RESPONSE_BODY" | python3 -m json.tool >&2

echo "$RESPONSE_BODY" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])'
