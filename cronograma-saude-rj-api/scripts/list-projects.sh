#!/usr/bin/env bash
# Uso: list-projects.sh [--archived]
set -euo pipefail

BASE_URL="https://cronograma.saude.rj.gov.br/api"
COOKIE_JAR="${CRONOGRAMA_COOKIE_JAR:-$HOME/.cache/cronograma-cookies.txt}"
mkdir -p "$(dirname "$COOKIE_JAR")"

URL="$BASE_URL/projects"
if [[ "${1:-}" == "--archived" ]]; then
  URL="$URL?archived=true"
fi

RESPONSE=$(curl -s -w '\n%{http_code}' -b "$COOKIE_JAR" "$URL")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
  echo "Erro ao listar projetos (HTTP $HTTP_CODE):" >&2
  echo "$RESPONSE_BODY" >&2
  exit 1
fi

echo "$RESPONSE_BODY" | python3 -m json.tool
