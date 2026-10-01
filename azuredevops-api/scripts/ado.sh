#!/usr/bin/env bash
# CLI único desta skill — delega para os scripts individuais via exec (mesmo padrão de `kc`
# na keycloak-api, `pb` na vault-factory, `nexus` na nuget-factory).
# Uso: ado <subcomando> [args...]
set -euo pipefail
# readlink -f resolve o symlink (ex: ~/.local/bin/ado criado pelo init.sh) até o script real,
# senão DIR apontaria para ~/.local/bin em vez desta pasta (mesmo tratamento de kc.sh).
DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
SUB="${1:-}"
shift || true

case "$SUB" in
  setup)            exec "$DIR/setup.sh" "$@" ;;
  alias)            exec "$DIR/aliases.sh" "$@" ;;
  work-items)       exec "$DIR/query-workitems.sh" "$@" ;;
  work-item)        exec "$DIR/get-workitem.sh" "$@" ;;
  epics)            exec "$DIR/list-epics.sh" "$@" ;;
  tree)             exec "$DIR/list-tree.sh" "$@" ;;
  export-workitems) exec "$DIR/export-workitems.sh" "$@" ;;
  wikis)            exec "$DIR/list-wikis.sh" "$@" ;;
  export-wiki)      exec "$DIR/export-wiki.sh" "$@" ;;
  *)
    cat >&2 <<'EOF'
Uso: ado <subcomando> [args...]

  setup <ORG>                                                       Cadastra o PAT da organização
  alias add <apelido> --org <ORG> --project <PROJETO> [--wiki <WIKI>]
  alias list
  alias remove <apelido>
  alias resolve <apelido>
  work-items <apelido> [--type TIPO] [--state ESTADO] [--title-contains TEXTO] [--top N|--all] [--json]
  work-item <apelido> <id> [--json]
  epics <apelido>
  tree <apelido> [--type TIPO-FILHO] [--feature-contains TEXTO]
  export-workitems <apelido> <destino> --epic <id> | --ids <id1,...> | --title-contains <texto> | --all [--type TIPO] [--state ESTADO] [--layout flat|docs] [--clean] [--dry-run] [--no-order-prefix]
  wikis <apelido>
  export-wiki <apelido> <path-da-wiki> <destino> [--wiki <NOME>]
EOF
    exit 1
    ;;
esac
