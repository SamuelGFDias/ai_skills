#!/usr/bin/env bash
# Exporta um path de uma wiki do Azure DevOps para arquivos .md locais, baixando os anexos
# referenciados (pasta .attachments do repositório da wiki) para uma pasta assets/ ao lado,
# com os links do markdown reescritos para apontar pra lá.
#
# Funciona clonando (raso) o repositório git por trás da wiki — é assim que o Azure DevOps
# guarda o conteúdo de verdade (cada página já é um .md); evita paginar a REST API
# página a página. Requer git.
#
# Uso:
#   scripts/export-wiki.sh <apelido> <path-da-wiki> <destino-local> [--wiki <nome-da-wiki>]
#
# path-da-wiki: prefixo do caminho da página na wiki (ex.: "Requisitos" ou
#               "Requisitos/Modulo-Usuario").
# destino-local: pasta onde salvar (cria docs/ e assets/ dentro dela).
#
# Limitação conhecida: a correspondência de path-da-wiki com os nomes de arquivo no
# repositório é heurística (sem acento, minúsculo, espaço~hífen), porque o Azure DevOps
# normaliza o título da página pro nome do arquivo. Confira a lista de páginas exportadas no
# final; se vier vazio, o helper lista as páginas disponíveis no repositório para ajustar o
# prefixo. Ainda não testado contra uma wiki real neste ambiente — o projeto usado para
# desenhar esta skill não tinha wiki provisionada (ver scripts/list-wikis.sh).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

ALIAS="${1:-}"; WIKI_PATH="${2:-}"; DEST="${3:-}"
if [ -z "$ALIAS" ] || [ -z "$WIKI_PATH" ] || [ -z "$DEST" ]; then
    echo "Uso: $0 <apelido> <path-da-wiki> <destino-local> [--wiki <nome-da-wiki>]" >&2
    exit 1
fi
shift 3
WIKI_OVERRIDE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --wiki) WIKI_OVERRIDE="$2"; shift 2 ;;
        *) echo "Opção desconhecida: $1" >&2; exit 1 ;;
    esac
done

ado_resolve_alias "$ALIAS"
ado_load_pat "$ADO_ORG"

WIKI_NAME="${WIKI_OVERRIDE:-$ADO_WIKI}"
if [ -z "$WIKI_NAME" ]; then
    echo "Nome da wiki não definido (nem --wiki, nem cadastrado no apelido '$ALIAS')." >&2
    echo "Rode: scripts/list-wikis.sh $ALIAS" >&2
    exit 1
fi

ORG_ENC="$(ado_urlenc "$ADO_ORG")"
PROJECT_ENC="$(ado_urlenc "$ADO_PROJECT")"
WIKI_ENC="$(ado_urlenc "$WIKI_NAME")"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

AUTH_HEADER="Authorization: Basic $(printf ':%s' "$ADO_PAT" | base64 -w0)"
echo "Clonando repositório da wiki '$WIKI_NAME'..."
git -c http.extraHeader="$AUTH_HEADER" clone --depth 1 --quiet \
    "https://dev.azure.com/${ORG_ENC}/${PROJECT_ENC}/_git/${WIKI_ENC}" "$TMPDIR/repo"

mkdir -p "$DEST"
python3 "$(dirname "$0")/export_wiki_helper.py" "$TMPDIR/repo" "$WIKI_PATH" "$DEST"
