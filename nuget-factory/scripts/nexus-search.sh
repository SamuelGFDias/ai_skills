#!/usr/bin/env bash
# Busca componentes por nome num repositorio do Nexus.
# Uso: nexus-search.sh <nome-ou-trecho> [repositorio]  (default: nuget-group)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib.sh"

NOME="${1:?Uso: nexus-search.sh <nome-ou-trecho> [repositorio]}"
REPO="${2:-nuget-group}"

nexus_exec 'curl -s -u "'"$NEXUS_USER"':$NEXUS_PASSWORD" "'"$NEXUS_HOST"'/service/rest/v1/search?repository='"$REPO"'&name='"$NOME"'"' \
  | jq -r '.items[] | "\(.id)\t\(.name)\t\(.version)\t\(.repository)"' \
  | { echo -e "ID\tNAME\tVERSION\tREPOSITORY"; cat; } \
  | column -t
