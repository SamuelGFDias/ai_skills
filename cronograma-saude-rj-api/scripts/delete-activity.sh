#!/usr/bin/env bash
# Uso: delete-activity.sh <activityId>
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Uso: delete-activity.sh <activityId>" >&2
  exit 1
fi

ACTIVITY_ID="$1"
BASE_URL="https://cronograma.saude.rj.gov.br/api"
COOKIE_JAR="${CRONOGRAMA_COOKIE_JAR:-$HOME/.cache/cronograma-cookies.txt}"
mkdir -p "$(dirname "$COOKIE_JAR")"

echo "Enviando DELETE /api/activities/$ACTIVITY_ID" >&2

RESPONSE=$(curl -s -w '\n%{http_code}' -b "$COOKIE_JAR" -X DELETE \
  "$BASE_URL/activities/$ACTIVITY_ID")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
  echo "Erro ao excluir atividade (HTTP $HTTP_CODE):" >&2
  echo "$RESPONSE_BODY" >&2
  exit 1
fi

echo "Atividade removida com sucesso." >&2
echo "$RESPONSE_BODY" | python3 -m json.tool
