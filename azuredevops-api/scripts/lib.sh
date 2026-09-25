#!/usr/bin/env bash
# Funções comuns a todos os scripts desta skill: resolver um apelido (alias) em
# {org, project, wiki}, carregar o PAT correspondente sem nunca imprimi-lo, e montar
# chamadas à API REST do Azure DevOps (api-version=7.1). Sourced por cada script — nunca
# executado diretamente.

set -euo pipefail

ADO_SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADO_PROJECTS_FILE="$ADO_SKILL_DIR/config/projects.json"
ADO_SECRETS_DIR="$HOME/.claude/secrets/azuredevops"
ADO_API_VERSION="7.1"

mkdir -p "$ADO_SKILL_DIR/config" "$ADO_SECRETS_DIR"
chmod 700 "$ADO_SECRETS_DIR" 2>/dev/null || true
[ -f "$ADO_PROJECTS_FILE" ] || echo '{}' > "$ADO_PROJECTS_FILE"

# Normaliza um nome para usar como nome de arquivo/caminho seguro: minúsculo, só [a-z0-9-].
ado_slug() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g'
}

# Resolve um apelido em ADO_ORG / ADO_PROJECT / ADO_WIKI (exporta as três variáveis).
ado_resolve_alias() {
    local alias="$1"
    local entry
    entry="$(jq -r --arg a "$alias" '.[$a] // empty' "$ADO_PROJECTS_FILE")"
    if [ -z "$entry" ]; then
        echo "Apelido '$alias' não encontrado." >&2
        local known
        known="$(jq -r 'keys | join(", ")' "$ADO_PROJECTS_FILE")"
        [ -n "$known" ] && echo "Apelidos cadastrados: $known" >&2
        echo "Cadastre com: scripts/aliases.sh add $alias --org <ORG> --project <PROJETO>" >&2
        exit 1
    fi
    ADO_ORG="$(printf '%s' "$entry" | jq -r '.org')"
    ADO_PROJECT="$(printf '%s' "$entry" | jq -r '.project')"
    ADO_WIKI="$(printf '%s' "$entry" | jq -r '.wiki // empty')"
}

# Carrega o PAT da org no ambiente (variável ADO_PAT), sem nunca imprimi-lo.
ado_load_pat() {
    local org="$1"
    local env_file="$ADO_SECRETS_DIR/$(ado_slug "$org").env"
    if [ ! -f "$env_file" ]; then
        echo "Credencial não encontrada para a org '$org' ($env_file)." >&2
        echo "Rode: scripts/setup.sh \"$org\"" >&2
        exit 1
    fi
    ADO_PAT="$(grep -m1 '^AZURE_DEVOPS_PAT=' "$env_file" | cut -d= -f2-)"
    if [ -z "$ADO_PAT" ]; then
        echo "Arquivo $env_file existe mas está sem AZURE_DEVOPS_PAT. Rode scripts/setup.sh de novo." >&2
        exit 1
    fi
}

# GET simples. Uso: ado_get "<url>"
ado_get() {
    curl -sS -u ":${ADO_PAT}" -H "Accept: application/json" "$1"
}

# POST com corpo JSON. Uso: ado_post "<url>" "<body-json>"
ado_post() {
    curl -sS -u ":${ADO_PAT}" -H "Accept: application/json" -H "Content-Type: application/json" \
        -X POST -d "$2" "$1"
}

# Percent-encode de um segmento de URL (org, projeto, nome de wiki podem ter espaço/ponto).
ado_urlenc() {
    python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1"
}

# Monta a URL base "https://dev.azure.com/{org}/{project}" já com percent-encoding.
ado_project_url() {
    echo "https://dev.azure.com/$(ado_urlenc "$ADO_ORG")/$(ado_urlenc "$ADO_PROJECT")"
}

# Constrói e executa uma consulta WIQL simples (tipo + estado opcional + título contendo
# texto opcional) e devolve os ids separados por vírgula (vazio se nenhum resultado).
# Uso: ado_wiql_ids <base_url> <tipo> <estado|""> <titulo-contem|""> <top>
ado_wiql_ids() {
    local base_url="$1" type="$2" state="$3" title_contains="$4" top="$5"
    local state_clause="" title_clause=""
    [ -n "$state" ] && state_clause="AND [System.State] = '${state//\'/\'\'}'"
    [ -n "$title_contains" ] && title_clause="AND [System.Title] CONTAINS '${title_contains//\'/\'\'}'"
    local wiql body ids_json
    wiql="SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = '${ADO_PROJECT//\'/\'\'}' AND [System.WorkItemType] = '${type//\'/\'\'}' ${state_clause} ${title_clause} ORDER BY [System.ChangedDate] DESC"
    body="$(jq -n --arg q "$wiql" '{query:$q}')"
    ids_json="$(ado_post "${base_url}/_apis/wit/wiql?api-version=${ADO_API_VERSION}" "$body")"
    printf '%s' "$ids_json" | jq -r --argjson top "$top" '[.workItems[]?.id][:$top] | join(",")' 2>/dev/null || true
}
