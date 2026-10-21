#!/usr/bin/env bash
# Localiza um repositório GitLab pelo nome e propõe o destino de clone.
# Uso: localizar-repo.sh <nome> [destino_base]
#   GITLAB_HOST  host da API (padrão gitlab.example.com)
# Saída TSV (match exato primeiro):
#   path_with_namespace  ssh_url  destino_proposto  destino_existe  arquivado
# Somente leitura: não clona nada.
set -euo pipefail

nome="${1:-}"
base="${2:-$HOME/dev/projects}"
if [ -z "$nome" ]; then
  echo "uso: $0 <nome> [destino_base]" >&2
  exit 2
fi

export GITLAB_HOST="${GITLAB_HOST:-gitlab.example.com}"

for bin in glab jq; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "ERRO: '$bin' não encontrado" >&2
    exit 3
  fi
done

if ! json="$(glab repo search -s "$nome" -F json 2>&1)"; then
  echo "ERRO: glab repo search falhou em $GITLAB_HOST: $json" >&2
  exit 4
fi

linhas="$(jq -r --arg n "$nome" '
  sort_by(if .path == $n then 0 else 1 end, .path_with_namespace)[]
  | [.path_with_namespace, .ssh_url_to_repo, .path, (.archived // false | tostring)]
  | @tsv' <<<"$json")"

if [ -z "$linhas" ]; then
  echo "NENHUM: nenhum repositório para '$nome' em $GITLAB_HOST" >&2
  exit 1
fi

printf 'path_with_namespace\tssh_url\tdestino_proposto\tdestino_existe\tarquivado\n'
while IFS=$'\t' read -r caminho ssh path arquivado; do
  destino="$base/$path"
  existe=nao
  if [ -e "$destino" ]; then
    existe=sim
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$caminho" "$ssh" "$destino" "$existe" "$arquivado"
done <<<"$linhas"
