#!/usr/bin/env bash
# Uso: update-activity.sh <activityId> <categoryId> <number> <description>
set -euo pipefail

if [[ $# -lt 4 ]]; then
  echo "Uso: update-activity.sh <activityId> <categoryId> <number> <description>" >&2
  exit 1
fi

ACTIVITY_ID="$1"
CATEGORY_ID="$2"
NUMBER="$3"
DESCRIPTION="$4"
BASE_URL="https://cronograma.saude.rj.gov.br/api"
COOKIE_JAR="${CRONOGRAMA_COOKIE_JAR:-$HOME/.cache/cronograma-cookies.txt}"
mkdir -p "$(dirname "$COOKIE_JAR")"

BODY=$(python3 -c '
import json, sys
categoryId, number, description = sys.argv[1:4]
print(json.dumps({
    "categoryId": categoryId,
    "number": int(number),
    "description": description,
}))
' "$CATEGORY_ID" "$NUMBER" "$DESCRIPTION")

echo "Enviando PUT /api/activities/$ACTIVITY_ID com body: $BODY" >&2

RESPONSE=$(curl -s -w '\n%{http_code}' -b "$COOKIE_JAR" -X PUT \
  "$BASE_URL/activities/$ACTIVITY_ID" \
  -H "Content-Type: application/json" \
  -d "$BODY")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
  echo "Erro ao atualizar atividade (HTTP $HTTP_CODE):" >&2
  echo "$RESPONSE_BODY" >&2
  exit 1
fi

echo "Atividade atualizada com sucesso:" >&2
echo "$RESPONSE_BODY" | python3 -m json.tool
