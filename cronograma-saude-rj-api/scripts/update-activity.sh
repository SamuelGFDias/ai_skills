#!/usr/bin/env bash
# Uso: update-activity.sh <activityId> <categoryId> <number> <description> [responsible]
set -euo pipefail

if [[ $# -lt 4 ]]; then
  echo "Uso: update-activity.sh <activityId> <categoryId> <number> <description> [responsible]" >&2
  exit 1
fi

ACTIVITY_ID="$1"
CATEGORY_ID="$2"
NUMBER="$3"
DESCRIPTION="$4"
RESPONSIBLE="${5:-}"

if [[ -z "$ACTIVITY_ID" ]]; then
  echo "Erro: activityId não pode ser vazio." >&2
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
categoryId, number, description, responsible = sys.argv[1:5]
body = {"categoryId": categoryId, "number": int(number), "description": description}
if responsible:
    body["responsible"] = responsible
print(json.dumps(body))
' "$CATEGORY_ID" "$NUMBER" "$DESCRIPTION" "$RESPONSIBLE")

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
