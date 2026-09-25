#!/usr/bin/env bash
# Cadastra o Personal Access Token (PAT) de uma organização Azure DevOps.
# O token nunca é impresso nem versionado: fica em ~/.claude/secrets/azuredevops/<org>.env
# (chmod 600), fora do repositório git desta skill — mesmo padrão de credenciais individuais
# usado pela skill keycloak-api.
#
# Uso:
#   scripts/setup.sh "<organização>"
#
# Depois de rodar, cadastre pelo menos um apelido de projeto com scripts/aliases.sh add.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

ORG="${1:-}"
if [ -z "$ORG" ]; then
    echo "Uso: $0 <ORG>" >&2
    exit 1
fi

ENV_FILE="$ADO_SECRETS_DIR/$(ado_slug "$ORG").env"

if [ -f "$ENV_FILE" ]; then
    echo "Já existe credencial cadastrada para '$ORG' ($ENV_FILE)."
    read -rp "Sobrescrever? [s/N] " CONFIRM
    case "$CONFIRM" in
        s|S) ;;
        *) echo "Cancelado."; exit 0 ;;
    esac
fi

ORG_ENC="$(ado_urlenc "$ORG")"
echo "Gere o PAT em: https://dev.azure.com/${ORG_ENC}/_usersSettings/tokens"
echo "Escopo mínimo recomendado: Work Items (Read) + Wiki (Read); ajuste conforme os comandos usados."
read -rsp "Cole o PAT (entrada oculta): " PAT
echo
if [ -z "$PAT" ]; then
    echo "PAT vazio, nada foi salvo." >&2
    exit 1
fi

(
    umask 177
    printf 'AZURE_DEVOPS_PAT=%s\n' "$PAT" > "$ENV_FILE"
)
chmod 600 "$ENV_FILE"

echo "Validando credencial..."
STATUS="$(curl -s -o /dev/null -w '%{http_code}' -u ":${PAT}" \
    "https://dev.azure.com/${ORG_ENC}/_apis/projects?api-version=${ADO_API_VERSION}&\$top=1")"
unset PAT

if [ "$STATUS" = "200" ]; then
    echo "OK — credencial validada e salva em $ENV_FILE."
else
    echo "Aviso: a API respondeu HTTP $STATUS ao validar. A credencial foi salva mesmo assim; confira org/PAT." >&2
fi

echo
echo "Próximo passo — cadastre um apelido de projeto, ex.:"
echo "  scripts/aliases.sh add <apelido> --org \"$ORG\" --project \"<Nome do Projeto>\""
