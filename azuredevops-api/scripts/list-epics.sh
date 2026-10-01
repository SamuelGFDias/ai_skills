#!/usr/bin/env bash
# Lista os Epics do projeto (id, estado, título, nº de User Stories descendentes) — usar antes
# de export-workitems.sh para perguntar ao usuário QUAL Epic exportar (nunca exportar o
# projeto inteiro por padrão: um projeto Azure DevOps costuma reunir vários sistemas).
#
# Uso: scripts/list-epics.sh <apelido>
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

ALIAS="${1:-}"
[ -n "$ALIAS" ] || { echo "Uso: $0 <apelido>" >&2; exit 1; }

ado_resolve_alias "$ALIAS"
ado_load_pat "$ADO_ORG"
BASE_URL="$(ado_project_url)"

EPIC_IDS="$(ado_wiql_ids "$BASE_URL" "Epic" "" "" 10000)"
[ -n "$EPIC_IDS" ] || { echo "Nenhum Epic em $ADO_PROJECT."; exit 0; }

BODY="$(jq -n --arg ids "$EPIC_IDS" '{ids: ($ids | split(",") | map(tonumber)), fields: ["System.Id","System.Title","System.State"]}')"
ado_post "${BASE_URL}/_apis/wit/workitemsbatch?api-version=${ADO_API_VERSION}" "$BODY" \
  | jq -r '.value[] | "\(.id)\t\(.fields["System.State"])\t\(.fields["System.Title"])"' \
  | sort -t$'\t' -k3 \
  | while IFS=$'\t' read -r ID STATE TITLE; do
      Q="$(jq -n --arg q "SELECT [System.Id] FROM WorkItemLinks WHERE [Source].[System.Id] = $ID AND [System.Links.LinkType] = 'System.LinkTypes.Hierarchy-Forward' AND [Target].[System.WorkItemType] = 'User Story' MODE (Recursive)" '{query:$q}')"
      RIDS="$(ado_post "${BASE_URL}/_apis/wit/wiql?api-version=${ADO_API_VERSION}" "$Q" | jq -r '[.workItemRelations[]? | select(.source != null) | .target.id] | unique | join(",")')"
      N=0
      if [ -n "$RIDS" ]; then
          N="$(ado_batch_all "$BASE_URL" "$RIDS" '{"fields":["System.WorkItemType"]}' | jq '[.value[] | select(.fields["System.WorkItemType"] == "User Story")] | length')"
      fi
      printf '%s\t%s\t%s\t%s US\n' "$ID" "$STATE" "$TITLE" "$N"
    done | column -t -s$'\t'
