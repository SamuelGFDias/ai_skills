#!/usr/bin/env bash
# Lista as wikis disponíveis num projeto Azure DevOps (nome, tipo, repositório git por trás).
# Rode antes do primeiro export-wiki.sh para descobrir o valor de --wiki, ou para cadastrar
# a wiki padrão do apelido (scripts/aliases.sh add ... --wiki <nome>).
#
# Uso: scripts/list-wikis.sh <apelido>
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

ALIAS="${1:-}"
[ -n "$ALIAS" ] || { echo "Uso: $0 <apelido>" >&2; exit 1; }

ado_resolve_alias "$ALIAS"
ado_load_pat "$ADO_ORG"
BASE_URL="$(ado_project_url)"

RESULT="$(ado_get "${BASE_URL}/_apis/wiki/wikis?api-version=${ADO_API_VERSION}")"
COUNT="$(printf '%s' "$RESULT" | jq -r '.count // 0')"

if [ "$COUNT" = "0" ]; then
    echo "Nenhuma wiki encontrada no projeto '$ADO_PROJECT'."
    exit 0
fi

{
  echo -e "NOME\tTIPO\tREPO_GIT"
  printf '%s' "$RESULT" | jq -r '.value[] | [.name, .type, (.remoteUrl // "-")] | @tsv'
} | column -t -s $'\t'
