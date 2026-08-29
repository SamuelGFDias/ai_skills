#!/usr/bin/env bash
# pb-find <termo-de-busca>
# Lista recursos do Passbolt cujo nome contenha o termo (case-insensitive).
# Só lista id + nome — nunca expõe secrets.
set -euo pipefail

usage() {
  echo "Uso: pb-find <termo-de-busca>" >&2
  echo "Exemplo: pb-find meu-app" >&2
  exit 1
}

QUERY="${1:-}"
[ -n "$QUERY" ] || usage

if ! command -v passbolt &>/dev/null; then
  echo "ERRO: passbolt (go-passbolt-cli) não está instalado ou fora do PATH." >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "ERRO: jq não está instalado." >&2
  exit 1
fi

MATCHES="$(passbolt list resources --json | jq -r --arg q "${QUERY,,}" '
    [.[] | select(((.name // .Name // "") | ascii_downcase) | contains($q))]
    | sort_by(.name // .Name)
    | .[] | "\(.id // .ID)  \(.name // .Name)"
  ')"

if [ -z "$MATCHES" ]; then
  echo "Nenhum recurso encontrado com nome contendo \"$QUERY\"." >&2
  exit 1
fi

echo "$MATCHES"
