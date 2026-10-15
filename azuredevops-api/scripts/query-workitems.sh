#!/usr/bin/env bash
# Lista work items (padrão: User Story) de um projeto Azure DevOps, via WIQL + batch get.
# Saída em tabela compacta (não o JSON bruto) para não gastar tokens do modelo com o
# boilerplate de _links/avatar/descriptor que a API devolve por item.
#
# Uso:
#   scripts/query-workitems.sh <apelido> [--type "User Story"] [--state <estado>] \
#       [--title-contains <texto>] [--top N|--all] [--json]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

ALIAS="${1:-}"
[ -n "$ALIAS" ] || { echo "Uso: $0 <apelido> [--type TIPO] [--state ESTADO] [--title-contains TEXTO] [--top N|--all] [--json]" >&2; exit 1; }
shift

TYPE="User Story"
STATE=""
TITLE_CONTAINS=""
TOP=200
JSON=0
while [ $# -gt 0 ]; do
    case "$1" in
        --type) TYPE="$2"; shift 2 ;;
        --state) STATE="$2"; shift 2 ;;
        --title-contains) TITLE_CONTAINS="$2"; shift 2 ;;
        --top) TOP="$2"; shift 2 ;;
        --all) TOP=1000000; shift ;;
        --json) JSON=1; shift ;;
        *) echo "Opção desconhecida: $1" >&2; exit 1 ;;
    esac
done

ado_resolve_alias "$ALIAS"
ado_load_pat "$ADO_ORG"
BASE_URL="$(ado_project_url)"

IDS="$(ado_wiql_ids "$BASE_URL" "$TYPE" "$STATE" "$TITLE_CONTAINS" "$TOP")"

if [ -z "$IDS" ]; then
    echo "Nenhum work item do tipo '$TYPE'${STATE:+ estado '$STATE'}${TITLE_CONTAINS:+ título contendo '$TITLE_CONTAINS'} em $ADO_PROJECT."
    exit 0
fi

BATCH_BODY="$(jq -n --arg ids "$IDS" \
    '{ids: ($ids | split(",") | map(tonumber)), fields: ["System.Id","System.Title","System.State","System.WorkItemType","System.AssignedTo","System.ChangedDate"]}')"
ITEMS_JSON="$(ado_post "${BASE_URL}/_apis/wit/workitemsbatch?api-version=${ADO_API_VERSION}" "$BATCH_BODY")"

if [ "$JSON" = "1" ]; then
    printf '%s\n' "$ITEMS_JSON"
    exit 0
fi

printf '%s\n' "$ITEMS_JSON" | jq -r '
  .value
  | sort_by(.fields["System.ChangedDate"]) | reverse
  | (["ID","ESTADO","TÍTULO","RESPONSÁVEL"] | @tsv),
    (.[] | [
        .fields["System.Id"],
        .fields["System.State"],
        .fields["System.Title"],
        (.fields["System.AssignedTo"].displayName // "-")
      ] | @tsv)
' | column -t -s $'\t'

TOTAL="$(printf '%s' "$ITEMS_JSON" | jq '.count')"
echo
echo "$TOTAL item(ns). Link: $BASE_URL/_workitems/edit/<ID>"
