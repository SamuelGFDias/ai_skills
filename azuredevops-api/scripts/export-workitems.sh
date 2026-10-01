#!/usr/bin/env bash
# Exporta work items (US, Tasks etc.) para Markdown local, baixando os anexos (imagens)
# referenciados na Descrição/Critérios de Aceitação para uma pasta assets/ ao lado, com os
# links do markdown reescritos para apontar pra lá.
#
# Uso:
#   scripts/export-workitems.sh <apelido> <destino-local> --epic <id-do-epic> [opções]
#   scripts/export-workitems.sh <apelido> <destino-local> --ids <id1,id2,...> [opções]
#   scripts/export-workitems.sh <apelido> <destino-local> --title-contains "<texto>" [opções]
#   scripts/export-workitems.sh <apelido> <destino-local> --all [opções]   (projeto inteiro)
# Opções: [--type "User Story"] [--state <estado>] [--top N] [--layout flat|docs]
#         [--clean] [--dry-run]
#
# Sem --epic/--ids/--title-contains/--all NADA é exportado: o script lista os Epics do projeto
# (um projeto costuma reunir vários sistemas) e sai com erro — pergunte ao usuário qual Epic.
# --epic: exporta os work items do --type descendentes do Epic; o destino já é o Epic (sem a
#   pasta dele). Demais modos gravam <Epic>/<Feature>/<id>-<slug>.md (hierarquia do Azure).
# --layout docs: .md em <destino>/docs/<Feature>/..., assets em <destino>/assets/ (padrão flat:
#   .md direto em <destino>/).
# --clean: remove arquivos gravados por exportação anterior (manifesto .ado-export.json) que
#   esta não regravou (US renomeada/movida/removida).
# --dry-run: mostra pastas e contagens (itens, imagens) sem baixar anexos nem gravar nada.
# --ids: lista explícita (ver "System.Parent" de cada item se houver Features duplicadas).
# --title-contains: gera ruído em backlogs com título repetido entre Features; prefira --epic.
# --all / --top: sem --all o resultado do WIQL por título/tipo/estado é cortado em --top (200)
#   COM aviso; --all traz tudo.
set -euo pipefail
CALLER_PWD="$PWD"  # o cd abaixo mudaria o destino relativo
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

ALIAS="${1:-}"; DEST="${2:-}"
if [ -z "$ALIAS" ] || [ -z "$DEST" ]; then
    echo "Uso: $0 <apelido> <destino-local> --epic <id> | --ids <id1,...> | --title-contains <texto> | --all [--type TIPO] [--state ESTADO] [--top N] [--layout flat|docs] [--clean] [--dry-run]" >&2
    exit 1
fi
shift 2
case "$DEST" in /*) ;; *) DEST="$CALLER_PWD/$DEST" ;; esac

IDS_ARG=""
EPIC=""
TYPE="User Story"
STATE=""
TITLE_CONTAINS=""
TOP=200
ALL=0
LAYOUT=flat
CLEAN=0
DRY_RUN=0
while [ $# -gt 0 ]; do
    case "$1" in
        --epic) EPIC="$2"; shift 2 ;;
        --ids) IDS_ARG="$2"; shift 2 ;;
        --title-contains) TITLE_CONTAINS="$2"; shift 2 ;;
        --type) TYPE="$2"; shift 2 ;;
        --state) STATE="$2"; shift 2 ;;
        --top) TOP="$2"; shift 2 ;;
        --all) ALL=1; TOP=1000000; shift ;;
        --layout) LAYOUT="$2"; shift 2 ;;
        --clean) CLEAN=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        *) echo "Opção desconhecida: $1" >&2; exit 1 ;;
    esac
done

case "$LAYOUT" in flat|docs) ;; *) echo "--layout deve ser flat ou docs." >&2; exit 1 ;; esac

if [ -z "$IDS_ARG" ] && [ -z "$TITLE_CONTAINS" ] && [ -z "$EPIC" ] && [ "$ALL" = 0 ]; then
    echo "Nada exportado: informe qual Epic exportar (--epic <id>), --ids, --title-contains ou --all." >&2
    echo "Epics de '$ALIAS':" >&2
    ./list-epics.sh "$ALIAS" >&2 || true
    exit 1
fi

ado_resolve_alias "$ALIAS"
ado_load_pat "$ADO_ORG"
BASE_URL="$(ado_project_url)"

if [ -n "$IDS_ARG" ]; then
    IDS="$IDS_ARG"
elif [ -n "$EPIC" ]; then
    Q="$(jq -n --arg q "SELECT [System.Id] FROM WorkItemLinks WHERE [Source].[System.Id] = ${EPIC//[^0-9]/} AND [System.Links.LinkType] = 'System.LinkTypes.Hierarchy-Forward' AND [Target].[System.WorkItemType] = '${TYPE//\'/\'\'}' MODE (Recursive)" '{query:$q}')"
    IDS="$(ado_post "${BASE_URL}/_apis/wit/wiql?api-version=${ADO_API_VERSION}" "$Q" \
        | jq -r '[.workItemRelations[]? | select(.source != null) | .target.id] | unique | join(",")')"
    # MODE (Recursive) devolve também os nós intermediários (Features): filtra pelo tipo pedido
    if [ -n "$IDS" ]; then
        IDS="$(ado_batch_all "$BASE_URL" "$IDS" '{"fields":["System.Id","System.WorkItemType"]}' \
            | jq -r --arg t "$TYPE" '[.value[] | select(.fields["System.WorkItemType"] == $t) | .id] | join(",")')"
    fi
else
    IDS="$(ado_wiql_ids "$BASE_URL" "$TYPE" "$STATE" "$TITLE_CONTAINS" "$TOP")"
fi

if [ -z "$IDS" ]; then
    echo "Nenhum work item encontrado para exportar."
    exit 0
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# um POST por 200 ids (workitemsbatch com $expand=all) em vez de um GET por item
ado_batch_all "$BASE_URL" "$IDS" '{"$expand":"all"}' | jq -c '.value[]' | while IFS= read -r ITEM; do
    printf '%s' "$ITEM" > "$TMPDIR/$(printf '%s' "$ITEM" | jq -r .id).json"
done
echo "Baixados $(ls "$TMPDIR"/*.json | wc -l) work item(ns), convertendo..."

ADO_LAYOUT="$LAYOUT" ADO_CLEAN="$CLEAN" ADO_DRY_RUN="$DRY_RUN" ADO_STRIP_EPIC="${EPIC//[^0-9]/}" ADO_PAT="$ADO_PAT" python3 "$(dirname "$0")/export_workitems_helper.py" "$TMPDIR" "$DEST" "$BASE_URL"
