#!/usr/bin/env bash
# Mostra a árvore Feature -> work item filho (padrão: User Story) de um projeto, em formato
# de pastas — para visualizar o que existe antes de decidir o que exportar com
# export-workitems.sh, sem baixar nada.
#
# Uso: scripts/list-tree.sh <apelido> [--type "User Story"] [--feature-contains <texto>]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

ALIAS="${1:-}"
[ -n "$ALIAS" ] || { echo "Uso: $0 <apelido> [--type TIPO] [--feature-contains TEXTO]" >&2; exit 1; }
shift

CHILD_TYPE="User Story"
FEATURE_CONTAINS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --type) CHILD_TYPE="$2"; shift 2 ;;
        --feature-contains) FEATURE_CONTAINS="$2"; shift 2 ;;
        *) echo "Opção desconhecida: $1" >&2; exit 1 ;;
    esac
done

ado_resolve_alias "$ALIAS"
ado_load_pat "$ADO_ORG"
BASE_URL="$(ado_project_url)"

FEATURE_IDS="$(ado_wiql_ids "$BASE_URL" "Feature" "" "$FEATURE_CONTAINS" 100000)"
if [ -z "$FEATURE_IDS" ]; then
    echo "Nenhuma Feature encontrada${FEATURE_CONTAINS:+ com título contendo '$FEATURE_CONTAINS'} em $ADO_PROJECT."
    exit 0
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

: > "$TMPDIR/pairs.tsv"
for FID in ${FEATURE_IDS//,/ }; do
    ado_get "${BASE_URL}/_apis/wit/workitems/${FID}?\$expand=relations&api-version=${ADO_API_VERSION}" \
      | jq -r --arg fid "$FID" '
          (.relations // [])[]
          | select(.rel == "System.LinkTypes.Hierarchy-Forward")
          | "\($fid)\t\(.url | split("/") | last)"
        ' >> "$TMPDIR/pairs.tsv"
done

if [ ! -s "$TMPDIR/pairs.tsv" ]; then
    echo "Nenhum filho encontrado para as Features de $ADO_PROJECT."
    exit 0
fi

ALL_IDS="$(cut -f1,2 "$TMPDIR/pairs.tsv" | tr '\t' '\n' | sort -un | paste -sd, -)"
ado_batch_all "$BASE_URL" "$ALL_IDS" '{"fields":["System.Id","System.Title","System.WorkItemType","System.State"]}' > "$TMPDIR/items.json"

python3 "$(dirname "$0")/print_tree_helper.py" "$TMPDIR/pairs.tsv" "$TMPDIR/items.json" "$CHILD_TYPE"
