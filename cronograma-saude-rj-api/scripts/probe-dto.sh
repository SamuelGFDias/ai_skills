#!/usr/bin/env bash
# Uso: probe-dto.sh <METHOD> <path> [json_body]
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Uso: probe-dto.sh <METHOD> <path> [json_body]" >&2
  echo "Ex: probe-dto.sh POST /projects '{}'" >&2
  exit 1
fi

METHOD="$1"
API_PATH="$2"
if [[ $# -ge 3 ]]; then
  JSON_BODY="$3"
else
  JSON_BODY='{}'
fi
BASE_URL="https://cronograma.saude.rj.gov.br/api"
COOKIE_JAR="${CRONOGRAMA_COOKIE_JAR:-$HOME/.cache/cronograma-cookies.txt}"
mkdir -p "$(dirname "$COOKIE_JAR")"

# Normaliza o path para sempre começar com /
case "$API_PATH" in
  /*) ;;
  *) API_PATH="/$API_PATH" ;;
esac

echo "Sondando $METHOD $BASE_URL$API_PATH com body: $JSON_BODY" >&2

RESPONSE=$(curl -s -w '\n%{http_code}' -b "$COOKIE_JAR" -X "$METHOD" \
  "$BASE_URL$API_PATH" \
  -H "Content-Type: application/json" \
  -d "$JSON_BODY")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

echo "HTTP $HTTP_CODE" >&2

if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
  # Resposta de erro (400/401/etc.) é o objetivo da sondagem: ela costuma
  # listar os campos exigidos pelo DTO na mensagem do class-validator.
  echo "$RESPONSE_BODY" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE_BODY"
  exit 1
fi

echo "$RESPONSE_BODY" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE_BODY"
