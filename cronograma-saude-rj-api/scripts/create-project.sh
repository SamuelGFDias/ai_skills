#!/usr/bin/env bash
# Uso: create-project.sh <name> [description]
#
# Cria um projeto (POST /api/projects) e imprime o `id` criado em stdout (para
# capturar com $(...)); o JSON completo vai para stderr. CreateProjectDto:
# `name` obrigatório (string, 1 a 200 caracteres) e `description` opcional.
# Só criar projeto novo quando o usuário pedir — antes, conferir com
# list-projects.sh --archived se já não existe um projeto para o mesmo fim.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Uso: create-project.sh <name> [description]" >&2
  exit 1
fi

NAME="$1"
DESCRIPTION="${2:-}"

if [[ -z "$NAME" ]]; then
  echo "Erro: name não pode ser vazio." >&2
  exit 1
fi
if [[ ${#NAME} -gt 200 ]]; then
  echo "Erro: name excede 200 caracteres (${#NAME})." >&2
  exit 1
fi

BASE_URL="https://cronograma.saude.rj.gov.br/api"
COOKIE_JAR="${CRONOGRAMA_COOKIE_JAR:-$HOME/.cache/cronograma-cookies.txt}"
mkdir -p "$(dirname "$COOKIE_JAR")"

BODY=$(python3 -c '
import json, sys
name, description = sys.argv[1:3]
body = {"name": name}
if description:
    body["description"] = description
print(json.dumps(body))
' "$NAME" "$DESCRIPTION")

echo "Enviando POST /api/projects com body: $BODY" >&2

RESPONSE=$(curl -s -w '\n%{http_code}' -b "$COOKIE_JAR" -X POST \
  "$BASE_URL/projects" \
  -H "Content-Type: application/json" \
  -d "$BODY")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
  echo "Erro ao criar projeto (HTTP $HTTP_CODE):" >&2
  echo "$RESPONSE_BODY" >&2
  exit 1
fi

echo "Projeto criado com sucesso:" >&2
echo "$RESPONSE_BODY" | python3 -m json.tool >&2

echo "$RESPONSE_BODY" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])'
