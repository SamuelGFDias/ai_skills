#!/usr/bin/env bash
# Cadastra/lista/remove apelidos de projeto (mapeiam um nome curto, ex. "meu-projeto", para
# {org, project, wiki}). Não guarda segredo nenhum — é seguro versionar
# (config/projects.json vai para o repo git desta skill, mesmo padrão dos "realms" da skill
# keycloak-api: cadastro de equipe, compartilhado entre máquinas via git).
#
# Uso:
#   scripts/aliases.sh add <apelido> --org <ORG> --project <PROJETO> [--wiki <WIKI>]
#   scripts/aliases.sh list
#   scripts/aliases.sh remove <apelido>
#   scripts/aliases.sh resolve <apelido>   # imprime {org,project,wiki} em JSON
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

CMD="${1:-}"
shift || true

case "$CMD" in
  add)
    ALIAS="${1:-}"
    [ -n "$ALIAS" ] || { echo "Uso: $0 add <apelido> --org <ORG> --project <PROJETO> [--wiki <WIKI>]" >&2; exit 1; }
    shift
    ORG=""; PROJECT=""; WIKI=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --org) ORG="$2"; shift 2 ;;
            --project) PROJECT="$2"; shift 2 ;;
            --wiki) WIKI="$2"; shift 2 ;;
            *) echo "Opção desconhecida: $1" >&2; exit 1 ;;
        esac
    done
    [ -n "$ORG" ] && [ -n "$PROJECT" ] || { echo "--org e --project são obrigatórios." >&2; exit 1; }
    TMP="$(mktemp)"
    jq --arg a "$ALIAS" --arg org "$ORG" --arg proj "$PROJECT" --arg wiki "$WIKI" \
       '.[$a] = {org: $org, project: $proj, wiki: (if $wiki == "" then null else $wiki end)}' \
       "$ADO_PROJECTS_FILE" > "$TMP"
    mv "$TMP" "$ADO_PROJECTS_FILE"
    echo "Apelido '$ALIAS' -> org='$ORG' project='$PROJECT' wiki='${WIKI:-<não definida>}'"
    ;;
  list)
    {
      echo -e "APELIDO\tORG\tPROJETO\tWIKI"
      jq -r 'to_entries[] | "\(.key)\t\(.value.org)\t\(.value.project)\t\(.value.wiki // "-")"' "$ADO_PROJECTS_FILE"
    } | column -t -s $'\t'
    ;;
  remove)
    ALIAS="${1:-}"
    [ -n "$ALIAS" ] || { echo "Uso: $0 remove <apelido>" >&2; exit 1; }
    TMP="$(mktemp)"
    jq --arg a "$ALIAS" 'del(.[$a])' "$ADO_PROJECTS_FILE" > "$TMP"
    mv "$TMP" "$ADO_PROJECTS_FILE"
    echo "Apelido '$ALIAS' removido (se existia)."
    ;;
  resolve)
    ALIAS="${1:-}"
    [ -n "$ALIAS" ] || { echo "Uso: $0 resolve <apelido>" >&2; exit 1; }
    ado_resolve_alias "$ALIAS"
    jq -n --arg org "$ADO_ORG" --arg proj "$ADO_PROJECT" --arg wiki "$ADO_WIKI" \
       '{org:$org, project:$proj, wiki:(if $wiki=="" then null else $wiki end)}'
    ;;
  *)
    echo "Uso: $0 {add|list|remove|resolve} ..." >&2
    exit 1
    ;;
esac
