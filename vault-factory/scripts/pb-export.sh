#!/usr/bin/env bash
# pb-export <resource-id-ou-nome> <input-file>
# Sobrescreve a nota/descrição de um recurso no Passbolt com o conteúdo de <input-file>.
# Pede confirmação antes de sobrescrever e nunca imprime o conteúdo no stdout/stderr.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

usage() {
  echo "Uso: pb-export <resource-id-ou-nome> <input-file>" >&2
  echo "Exemplo: pb-export <resource-id> ./src/Projeto.Infra.CrossCutting/.env" >&2
  echo "         pb-export \"env dev\" ./src/Projeto.Infra.CrossCutting/.env" >&2
  exit 1
}

RAW_ID="${1:-}"
IN_FILE="${2:-}"

[ -n "$RAW_ID" ] && [ -n "$IN_FILE" ] || usage

if ! command -v passbolt &>/dev/null; then
  echo "ERRO: passbolt (go-passbolt-cli) não está instalado ou fora do PATH." >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "ERRO: jq não está instalado." >&2
  exit 1
fi

if ! RESOURCE_ID="$(resolve_resource_id "$RAW_ID")"; then
  exit 1
fi

if [ ! -f "$IN_FILE" ]; then
  echo "ERRO: arquivo não encontrado: $IN_FILE" >&2
  exit 1
fi

if [ ! -s "$IN_FILE" ]; then
  echo "ERRO: arquivo está vazio: $IN_FILE" >&2
  exit 1
fi

echo "Validando recurso $RESOURCE_ID no Passbolt..."

if ! passbolt get resource --id "$RESOURCE_ID" --json >/dev/null; then
  echo "ERRO: recurso não encontrado ou inacessível: $RESOURCE_ID" >&2
  exit 1
fi

RESOURCE_NAME="$(passbolt get resource --id "$RESOURCE_ID" --json | jq -r '.name // .Name // empty' 2>/dev/null || true)"

echo "Recurso: ${RESOURCE_NAME:-$RESOURCE_ID}"
echo "Arquivo origem: $IN_FILE"
echo
echo "Isso SOBRESCREVE a nota atual do recurso no Passbolt com o conteúdo do arquivo acima."
read -r -p "Confirmar? [s/N] " confirm

case "$confirm" in
  s|S|sim|SIM) ;;
  *) echo "Cancelado."; exit 0 ;;
esac

passbolt update resource \
  --id "$RESOURCE_ID" \
  --description "$(cat "$IN_FILE")"

echo "OK: nota do recurso $RESOURCE_ID atualizada a partir de $IN_FILE."
