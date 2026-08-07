#!/usr/bin/env bash
# pb — CLI único que delega para os scripts individuais da skill passbolt-cli.
# Nenhuma lógica de negócio mora aqui; cada subcomando é um exec para o script correspondente.
set -euo pipefail

# readlink -f resolve o symlink (ex: ~/.local/bin/pb criado pelo init.sh) até o script real,
# senão SCRIPT_DIR apontaria para ~/.local/bin em vez desta pasta.
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

usage() {
  cat >&2 <<'EOF'
pb — CLI da skill passbolt-cli (cofre Passbolt da SES-RJ)

Uso: pb <subcomando> [args...]

  find <termo>                        Lista recursos cujo nome contenha o termo (id + nome, sem secrets).
  import <id-ou-nome> <output-path>   Grava a nota/descrição de um recurso num arquivo (sem ecoar o conteúdo).
  export <id-ou-nome> <input-file>    Sobrescreve a nota/descrição de um recurso com o conteúdo de um arquivo
                                       (pede confirmação, sem ecoar o conteúdo).

Em import/export, <id-ou-nome> aceita tanto o UUID do recurso quanto um trecho do nome
(case-insensitive). Se o trecho casar mais de um recurso, a lista de candidatos aparece no erro —
refine o termo ou use `pb find` para descobrir o UUID exato.

Exemplos:
  pb find dev
  pb import 26d96316-0a5e-4a94-b1da-e7e75ac3df5b ./.env
  pb import "biae dev" ./src/Biae.Infra.CrossCutting/ConfigurationEnvironment/.env.Development
  pb export "biae dev" ./.env
EOF
}

SUBCOMMAND="${1:-}"
[ -n "$SUBCOMMAND" ] && shift || true

case "$SUBCOMMAND" in
  find)               exec "$SCRIPT_DIR/pb-find.sh" "$@" ;;
  import)              exec "$SCRIPT_DIR/pb-import.sh" "$@" ;;
  export)              exec "$SCRIPT_DIR/pb-export.sh" "$@" ;;
  ""|-h|--help|help)   usage; exit 0 ;;
  *)
    echo "Subcomando desconhecido: $SUBCOMMAND" >&2
    echo >&2
    usage
    exit 1
    ;;
esac
