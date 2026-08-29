#!/usr/bin/env bash
# pb-import <resource-id-ou-nome> <output-path>
# Busca a nota/descrição de um recurso no Passbolt e grava em <output-path>.
# Nunca imprime o conteúdo da nota no stdout/stderr.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

usage() {
  echo "Uso: pb-import <resource-id-ou-nome> <output-path>" >&2
  echo "Exemplo: pb-import <resource-id> ./src/Projeto.Infra.CrossCutting/.env" >&2
  echo "         pb-import \"env dev\" ./src/Projeto.Infra.CrossCutting/.env" >&2
  exit 1
}

RAW_ID="${1:-}"
OUT_PATH="${2:-}"

[ -n "$RAW_ID" ] && [ -n "$OUT_PATH" ] || usage

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

OUT_DIR="$(dirname "$OUT_PATH")"
mkdir -p "$OUT_DIR"

echo "Buscando nota do recurso $RESOURCE_ID..."

tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT

passbolt get resource --id "$RESOURCE_ID" --json \
  | jq -r '
      .secret.description //
      .secret.Description //
      .Secret.description //
      .Secret.Description //
      .metadata.description //
      .Metadata.description //
      .description //
      .Description //
      empty
    ' \
  | sed 's/\r$//' > "$tmp_file"

if [ ! -s "$tmp_file" ]; then
  echo "ERRO: nenhuma nota/descrição encontrada nesse recurso." >&2
  echo "Inspecione a estrutura (isso pode expor o secret no terminal, cuidado):" >&2
  echo "  passbolt get resource --id \"$RESOURCE_ID\" --json | jq ." >&2
  exit 1
fi

if [ -e "$OUT_PATH" ]; then
  read -r -p "Arquivo $OUT_PATH já existe. Sobrescrever? [s/N] " confirm
  case "$confirm" in
    s|S|sim|SIM) ;;
    *) echo "Cancelado."; exit 1 ;;
  esac
fi

mv "$tmp_file" "$OUT_PATH"
chmod 600 "$OUT_PATH"
trap - EXIT

echo "OK: nota gravada em $OUT_PATH (não exibida)."
