#!/usr/bin/env bash
# Detalha um work item: título, estado, responsável e descrição/critérios de aceitação
# convertidos de HTML para texto simples — a API do Azure DevOps devolve esses campos como
# HTML bruto cheio de estilo inline (blockquote/span aninhados), não vale a pena gastar
# tokens do modelo lendo isso direto.
#
# Uso:
#   scripts/get-workitem.sh <apelido> <id> [--json]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

ALIAS="${1:-}"; ID="${2:-}"
[ -n "$ALIAS" ] && [ -n "$ID" ] || { echo "Uso: $0 <apelido> <id> [--json]" >&2; exit 1; }
JSON=0
[ "${3:-}" = "--json" ] && JSON=1

ado_resolve_alias "$ALIAS"
ado_load_pat "$ADO_ORG"
BASE_URL="$(ado_project_url)"

ITEM_JSON="$(ado_get "${BASE_URL}/_apis/wit/workitems/${ID}?api-version=${ADO_API_VERSION}")"

if [ "$JSON" = "1" ]; then
    printf '%s\n' "$ITEM_JSON"
    exit 0
fi

# Grava em arquivo temporário em vez de usar stdin: um heredoc de script Python (abaixo)
# tomaria o próprio stdin do processo, então não dá para também alimentar o JSON por pipe.
TMPFILE="$(mktemp)"
trap 'rm -f "$TMPFILE"' EXIT
printf '%s' "$ITEM_JSON" > "$TMPFILE"
python3 "$(dirname "$0")/workitem_to_text.py" "$TMPFILE" "$BASE_URL" "$ID"
