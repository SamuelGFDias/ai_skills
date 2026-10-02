#!/usr/bin/env bash
# Uso: update-activity-day.sh <activityId> <date YYYY-MM-DD> <status>
# status aceita: F (A Fazer), A (Em andamento), C (Concluído), ou "" (vazio, remove o registro do dia).
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "Uso: update-activity-day.sh <activityId> <date YYYY-MM-DD> <status>" >&2
  echo "status: F (A Fazer) | A (Em andamento) | C (Concluído) | \"\" (remove o registro)" >&2
  exit 1
fi

ACTIVITY_ID="$1"
DATE="$2"
STATUS="$3"

if [[ -z "$ACTIVITY_ID" ]]; then
  echo "Erro: activityId não pode ser vazio." >&2
  exit 1
fi
if [[ -z "$DATE" ]]; then
  echo "Erro: date não pode ser vazio." >&2
  exit 1
fi

BASE_URL="https://cronograma.saude.rj.gov.br/api"
COOKIE_JAR="${CRONOGRAMA_COOKIE_JAR:-$HOME/.cache/cronograma-cookies.txt}"
mkdir -p "$(dirname "$COOKIE_JAR")"

BODY=$(python3 -c '
import json, sys
activityId, date, status = sys.argv[1:4]
body = {"activityId": activityId, "date": date}
# status "" é rejeitado (HTTP 400); para remover o dia, omite-se o campo status.
if status:
    body["status"] = status
print(json.dumps(body))
' "$ACTIVITY_ID" "$DATE" "$STATUS")

echo "Enviando PUT /api/activity-days com body: $BODY" >&2

RESPONSE=$(curl -s -w '\n%{http_code}' -b "$COOKIE_JAR" -X PUT \
  "$BASE_URL/activity-days" \
  -H "Content-Type: application/json" \
  -d "$BODY")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
  echo "Erro ao atualizar dia da atividade (HTTP $HTTP_CODE):" >&2
  echo "$RESPONSE_BODY" >&2
  exit 1
fi

echo "Dia da atividade atualizado com sucesso:" >&2
echo "$RESPONSE_BODY" | python3 -m json.tool
