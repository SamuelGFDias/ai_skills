#!/usr/bin/env bash
# kc — CLI único que delega para os scripts individuais da skill keycloak-api.
# Nenhuma lógica de API mora aqui; cada subcomando é um exec para o script correspondente.
set -euo pipefail

# readlink -f resolve o symlink (ex: ~/.local/bin/kc criado pelo init.sh) até o script real,
# senão SCRIPT_DIR apontaria para ~/.local/bin em vez desta pasta.
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

usage() {
  cat >&2 <<'EOF'
kc — CLI da skill keycloak-api (consulta/sincroniza a Admin REST API do Keycloak)

Uso: kc <subcomando> [args...]

Setup (uma vez por alias):
  setup-credentials                                  Cadastra um novo alias (base URL, realm, client id/secret).
                                                       Secret lida com read -s, nunca ecoada.

Consulta:
  list-aliases                                        Lista os aliases cadastrados (alias, base URL, realm, client id — sem secret).
  token <alias>                                      Imprime um access_token (uso interno; evite mostrar ao usuário).
  list-clients <alias>                                Lista os clients do realm (sem secret).
  realm-roles <alias>                                 Lista as roles de nível de realm (JSON).
  list-groups <alias>                                 Lista os groups do realm (árvore completa).
  group-detail <alias> <groupId>                      Detalha um group: subgrupos, membros, role mappings.
  client-roles <alias> <clientId>                     Lista as roles de um client pelo nome (ex: meu-app).

Criação pontual:
  create-client-role <alias> <clientId> <roleName> [descricao]
                                                       Cria uma role num client. Idempotente.

Espelhamento entre ambientes (idempotente — seguro rodar de novo):
  mirror-client-roles <sourceAlias> <targetAlias> <clientIdName>
                                                       Cria no destino as roles que existem na origem e faltam nele.
  mirror-group-roles <sourceAlias> <targetAlias> <groupPath> <clientIdName> [--recursive]
                                                       Espelha client-role-mappings de um group. Cria o group se faltar.
                                                       --recursive aplica também aos subgrupos.

Exemplos:
  kc setup-credentials
  kc client-roles realm-dev-meu-app meu-app
  kc mirror-client-roles realm-dev-meu-app realm-stg-meu-app meu-app
  kc mirror-group-roles realm-dev-meu-app realm-stg-meu-app "/MeuApp" meu-app --recursive

Ordem recomendada ao espelhar um client completo: mirror-client-roles antes de mirror-group-roles
(as roles precisam existir no destino antes de mapeá-las nos groups).
EOF
}

SUBCOMMAND="${1:-}"
[ -n "$SUBCOMMAND" ] && shift || true

case "$SUBCOMMAND" in
  list-aliases)          exec "$SCRIPT_DIR/kc-list-aliases.sh" "$@" ;;
  token)                exec "$SCRIPT_DIR/kc-token.sh" "$@" ;;
  list-clients)          exec "$SCRIPT_DIR/kc-list-clients.sh" "$@" ;;
  realm-roles)           exec "$SCRIPT_DIR/kc-realm-roles.sh" "$@" ;;
  list-groups)           exec "$SCRIPT_DIR/kc-list-groups.sh" "$@" ;;
  group-detail)          exec "$SCRIPT_DIR/kc-group-detail.sh" "$@" ;;
  client-roles)          exec "$SCRIPT_DIR/kc-client-roles.sh" "$@" ;;
  create-client-role)    exec "$SCRIPT_DIR/kc-create-client-role.sh" "$@" ;;
  mirror-client-roles)   exec "$SCRIPT_DIR/kc-mirror-client-roles.sh" "$@" ;;
  mirror-group-roles)    exec "$SCRIPT_DIR/kc-mirror-group-roles.sh" "$@" ;;
  setup-credentials)     exec "$SCRIPT_DIR/setup-credentials.sh" "$@" ;;
  ""|-h|--help|help)     usage; exit 0 ;;
  *)
    echo "Subcomando desconhecido: $SUBCOMMAND" >&2
    echo >&2
    usage
    exit 1
    ;;
esac
