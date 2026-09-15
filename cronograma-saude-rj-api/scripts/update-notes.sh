#!/usr/bin/env bash
# Uso: update-notes.sh <activityId> <notes>
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Uso: update-notes.sh <activityId> <notes>" >&2
  exit 1
fi

ACTIVITY_ID="$1"
NOTES="$2"
BASE_URL="https://cronograma.saude.rj.gov.br/api"
COOKIE_JAR="${CRONOGRAMA_COOKIE_JAR:-$HOME/.cache/cronograma-cookies.txt}"
mkdir -p "$(dirname "$COOKIE_JAR")"

BODY=$(python3 -c '
import json, sys
notes = sys.argv[1]
print(json.dumps({
    "notes": notes,
}))
' "$NOTES")

echo "Enviando PATCH /api/activities/$ACTIVITY_ID/notes com body: $BODY" >&2

RESPONSE=$(curl -s -w '\n%{http_code}' -b "$COOKIE_JAR" -X PATCH \
  "$BASE_URL/activities/$ACTIVITY_ID/notes" \
  -H "Content-Type: application/json" \
  -d "$BODY")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
  echo "Erro ao atualizar notas (HTTP $HTTP_CODE):" >&2
  echo "$RESPONSE_BODY" >&2
  exit 1
fi

echo "Notas atualizadas com sucesso:" >&2
echo "$RESPONSE_BODY" | python3 -m json.tool
