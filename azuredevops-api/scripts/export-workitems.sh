#!/usr/bin/env bash
# Exporta work items (US, Tasks etc.) para Markdown local, baixando os anexos (imagens)
# referenciados na Descrição/Critérios de Aceitação para uma pasta assets/ ao lado, com os
# links do markdown reescritos para apontar pra lá.
#
# Uso:
#   scripts/export-workitems.sh <apelido> <destino-local> --ids <id1,id2,...>
#   scripts/export-workitems.sh <apelido> <destino-local> --title-contains "<texto>" \
#       [--type "User Story"] [--state <estado>] [--top N]
#
# --ids: lista explícita de ids (uso recomendado depois de já ter investigado e escolhido
#   exatamente quais items exportar — ex.: quando o mesmo título aparece em vários work items
#   por o backlog ter Features duplicadas, ver "System.Parent" de cada item para desambiguar).
# --title-contains: atalho para quando o filtro por WIQL já é suficiente (poucos resultados,
#   sem ambiguidade). Gera muito ruído em backlogs com título repetido entre Features
#   diferentes — nesse caso, prefira investigar e usar --ids.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

ALIAS="${1:-}"; DEST="${2:-}"
if [ -z "$ALIAS" ] || [ -z "$DEST" ]; then
    echo "Uso: $0 <apelido> <destino-local> --ids <id1,id2,...> | --title-contains <texto> [--type TIPO] [--state ESTADO] [--top N]" >&2
    exit 1
fi
shift 2

IDS_ARG=""
TYPE="User Story"
STATE=""
TITLE_CONTAINS=""
TOP=200
while [ $# -gt 0 ]; do
    case "$1" in
        --ids) IDS_ARG="$2"; shift 2 ;;
        --title-contains) TITLE_CONTAINS="$2"; shift 2 ;;
        --type) TYPE="$2"; shift 2 ;;
        --state) STATE="$2"; shift 2 ;;
        --top) TOP="$2"; shift 2 ;;
        *) echo "Opção desconhecida: $1" >&2; exit 1 ;;
    esac
done

if [ -z "$IDS_ARG" ] && [ -z "$TITLE_CONTAINS" ]; then
    echo "Informe --ids <id1,id2,...> ou --title-contains <texto>." >&2
    exit 1
fi

ado_resolve_alias "$ALIAS"
ado_load_pat "$ADO_ORG"
BASE_URL="$(ado_project_url)"

if [ -n "$IDS_ARG" ]; then
    IDS="$IDS_ARG"
else
    IDS="$(ado_wiql_ids "$BASE_URL" "$TYPE" "$STATE" "$TITLE_CONTAINS" "$TOP")"
fi

if [ -z "$IDS" ]; then
    echo "Nenhum work item encontrado para exportar."
    exit 0
fi

mkdir -p "$DEST/docs" "$DEST/assets"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

N=0
for ID in ${IDS//,/ }; do
    N=$((N+1))
    ado_get "${BASE_URL}/_apis/wit/workitems/${ID}?api-version=${ADO_API_VERSION}" > "$TMPDIR/$ID.json"
done
echo "Baixados $N work item(ns), convertendo..."

ADO_PAT="$ADO_PAT" python3 "$(dirname "$0")/export_workitems_helper.py" "$TMPDIR" "$DEST" "$BASE_URL"
