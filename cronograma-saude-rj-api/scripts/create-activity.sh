#!/usr/bin/env bash
# Uso: create-activity.sh <projectId> <categoryId> <number> <description>
set -euo pipefail

if [[ $# -lt 4 ]]; then
  echo "Uso: create-activity.sh <projectId> <categoryId> <number> <description>" >&2
  exit 1
fi

PROJECT_ID="$1"
CATEGORY_ID="$2"
NUMBER="$3"
DESCRIPTION="$4"

if [[ -z "$PROJECT_ID" ]]; then
  echo "Erro: projectId não pode ser vazio." >&2
  exit 1
fi
if [[ -z "$CATEGORY_ID" ]]; then
  echo "Erro: categoryId não pode ser vazio." >&2
  exit 1
fi
if [[ -z "$NUMBER" ]]; then
  echo "Erro: number não pode ser vazio." >&2
  exit 1
fi
if [[ -z "$DESCRIPTION" ]]; then
  echo "Erro: description não pode ser vazio." >&2
  exit 1
fi

BASE_URL="https://cronograma.saude.rj.gov.br/api"
COOKIE_JAR="${CRONOGRAMA_COOKIE_JAR:-$HOME/.cache/cronograma-cookies.txt}"
mkdir -p "$(dirname "$COOKIE_JAR")"

BODY=$(python3 -c '
import json, sys
projectId, categoryId, number, description = sys.argv[1:5]
print(json.dumps({
    "projectId": projectId,
    "categoryId": categoryId,
    "number": int(number),
    "description": description,
}))
' "$PROJECT_ID" "$CATEGORY_ID" "$NUMBER" "$DESCRIPTION")

echo "Enviando POST /api/activities com body: $BODY" >&2

RESPONSE=$(curl -s -w '\n%{http_code}' -b "$COOKIE_JAR" -X POST \
  "$BASE_URL/activities" \
  -H "Content-Type: application/json" \
  -d "$BODY")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
  echo "Erro ao criar atividade (HTTP $HTTP_CODE):" >&2
  echo "$RESPONSE_BODY" >&2
  exit 1
fi

echo "Atividade criada com sucesso:" >&2
echo "$RESPONSE_BODY" | python3 -m json.tool >&2

echo "$RESPONSE_BODY" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])'
