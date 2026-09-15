#!/usr/bin/env bash
# Uso: list-activities.sh <projectId> [categoryId]
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Uso: list-activities.sh <projectId> [categoryId]" >&2
  exit 1
fi

PROJECT_ID="$1"
CATEGORY_ID="${2:-}"
BASE_URL="https://cronograma.saude.rj.gov.br/api"
COOKIE_JAR="${CRONOGRAMA_COOKIE_JAR:-$HOME/.cache/cronograma-cookies.txt}"
mkdir -p "$(dirname "$COOKIE_JAR")"

RESPONSE=$(curl -s -w '\n%{http_code}' -b "$COOKIE_JAR" "$BASE_URL/activities?projectId=$PROJECT_ID")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
  echo "Erro ao listar atividades (HTTP $HTTP_CODE):" >&2
  echo "$RESPONSE_BODY" >&2
  exit 1
fi

if [[ -n "$CATEGORY_ID" ]]; then
  echo "$RESPONSE_BODY" | python3 -c '
import json, sys
categoryId = sys.argv[1]
data = json.load(sys.stdin)
items = data if isinstance(data, list) else data.get("data", data)
# A API retorna o campo em snake_case (category_id), não camelCase.
filtered = [item for item in items if item.get("category_id") == categoryId]
print(json.dumps(filtered, indent=2, ensure_ascii=False))
' "$CATEGORY_ID"
else
  echo "$RESPONSE_BODY" | python3 -m json.tool
fi
