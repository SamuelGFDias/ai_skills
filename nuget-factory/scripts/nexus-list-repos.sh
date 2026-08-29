#!/usr/bin/env bash
# Lista os repositorios configurados no Nexus (formato, tipo, url).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib.sh"

{
  echo -e "NAME\tFORMAT\tTYPE\tURL"
  nexus_exec 'curl -s -u "'"$NEXUS_USER"':$NEXUS_PASSWORD" "'"$NEXUS_HOST"'/service/rest/v1/repositories"' \
    | jq -r '.[] | "\(.name)\t\(.format)\t\(.type)\t\(.url)"'
} | column -t
