#!/usr/bin/env bash
# Funções compartilhadas pelos scripts nexus-*.sh
set -euo pipefail

NEXUS_HOST="https://nexus.saude.rj.gov.br"
NEXUS_USER="samuel.dias"
NEXUS_PASSBOLT_RESOURCE_ID="3ccc4fa5-4c5c-47b9-aa21-735f5cd9a89d"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Comando obrigatorio ausente: $1" >&2
    exit 1
  }
}

require_cmd curl
require_cmd jq
require_cmd passbolt

# Executa um comando bash recebendo NEXUS_PASSWORD ja resolvido pelo passbolt exec,
# sem nunca deixar a senha visivel no shell pai ou no historico.
nexus_exec() {
  local cmd="$1"
  NEXUS_PASSWORD="passbolt://${NEXUS_PASSBOLT_RESOURCE_ID}" \
    passbolt exec -- bash -c "$cmd"
}
