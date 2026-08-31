#!/usr/bin/env bash
# Uso: list-categories.sh <projectId>
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Uso: list-categories.sh <projectId>" >&2
  exit 1
fi

PROJECT_ID="$1"
BASE_URL="https://cronograma.saude.rj.gov.br/api"
COOKIE_JAR="${CRONOGRAMA_COOKIE_JAR:-$HOME/.cache/cronograma-cookies.txt}"
mkdir -p "$(dirname "$COOKIE_JAR")"

RESPONSE=$(curl -s -w '\n%{http_code}' -b "$COOKIE_JAR" "$BASE_URL/categories?projectId=$PROJECT_ID")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
  echo "Erro ao listar categorias (HTTP $HTTP_CODE):" >&2
  echo "$RESPONSE_BODY" >&2
  exit 1
fi

echo "$RESPONSE_BODY" | python3 -m json.tool
