#!/usr/bin/env bash
# Remove um componente do Nexus pelo id (obtido via nexus-search.sh). Pede confirmacao.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib.sh"

ID="${1:?Uso: nexus-delete-component.sh <component-id>}"

read -r -p "Confirma remocao do componente '$ID' no Nexus? [y/N] " resp
[[ "$resp" =~ ^[Yy]$ ]] || { echo "Cancelado."; exit 0; }

STATUS=$(nexus_exec 'curl_user_cfg | curl -s -o /dev/null -w "%{http_code}" -K - -X DELETE "$NX_HOST/service/rest/v1/components/$NX_ID"' NX_HOST="$NEXUS_HOST" NX_ID="$ID")
if [[ "$STATUS" == "204" ]]; then
  echo "OK: componente removido (204)."
else
  echo "Falha: HTTP $STATUS" >&2
  exit 1
fi
