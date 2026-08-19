#!/usr/bin/env bash
# CLI unico da skill nexus-nuget. Delega para os scripts individuais.
set -euo pipefail
# readlink -f resolve o symlink (ex: ~/.local/bin/nexus criado pelo init.sh) ate o script real,
# senao DIR apontaria para ~/.local/bin em vez desta pasta.
DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

SUBCOMANDO="${1:-}"
[[ $# -gt 0 ]] && shift || true

case "$SUBCOMANDO" in
  list-repos)
    exec "$DIR/nexus-list-repos.sh" "$@"
    ;;
  search)
    exec "$DIR/nexus-search.sh" "$@"
    ;;
  delete-component)
    exec "$DIR/nexus-delete-component.sh" "$@"
    ;;
  configure-project)
    exec "$DIR/nexus-configure-project.sh" "$@"
    ;;
  *)
    cat >&2 <<EOF
Uso: nexus <subcomando> [args]

Subcomandos:
  list-repos                                Lista repositorios do Nexus
  search <nome> [repositorio]               Busca componentes (default: nuget-group)
  delete-component <component-id>           Remove um componente (com confirmacao)
  configure-project <dir> [--hosted]        Gera NuGet.Config apontando pro Nexus SES
EOF
    exit 1
    ;;
esac
