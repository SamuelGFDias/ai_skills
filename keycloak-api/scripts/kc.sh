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

Cadastro (realm e credencial são configurados separadamente):
  setup-realm                                         Cadastra/edita um realm (alias, base URL, nome do realm).
  setup-client                                        Cadastra/edita um client (escolhe o realm num menu; secret
                                                        mascarada com * enquanto você digita/cola, pra conferir
                                                        visualmente que colou certo e não colou em dobro).
  setup-user                                          Cadastra/edita uma credencial de usuário (username/senha,
                                                        grant_type=password) — para operações fora do escopo de
                                                        um client, quando não há service account habilitado.
  delete-client <alias>                               Remove um client cadastrado (só o arquivo local; pede
                                                        confirmação [s/N]; não afeta o client no Keycloak).
  delete-user <alias>                                 Remove uma credencial de usuário cadastrada (idem).

Consulta de cadastro local:
  list-realms                                         Lista os realms cadastrados (alias, base URL, realm).
  list-clients-config                                 Lista os clients cadastrados (alias, realm, client id — sem secret).
  list-users-config                                   Lista os usuários cadastrados (alias, realm, client id, username — sem senha).

Consulta na API do Keycloak (1º argumento aceita <credAlias> de client OU de user; nos 5
comandos abaixo também aceita <realmAlias> — ver modo automático mais abaixo):
  token <credAlias>                                   Imprime um access_token (uso interno; evite mostrar ao usuário).
  list-clients <credAlias|realmAlias> [realmDestino]  Lista os clients do realm (sem secret).
  realm-roles <credAlias|realmAlias> [realmDestino]   Lista as roles de nível de realm (JSON).
  list-groups <credAlias|realmAlias> [realmDestino]   Lista os groups do realm (árvore completa).
  group-detail <credAlias|realmAlias> <groupId> [realmDestino]
                                                       Detalha um group: subgrupos, membros, role mappings.
  client-roles <credAlias|realmAlias> <clientId> [realmDestino]
                                                       Lista as roles de um client pelo nome (ex: biae).

  realmDestino (opcional, com <credAlias>): consulta outro realm da MESMA instância Keycloak
  da credencial, usando o token dela — cobre o padrão de admin do realm master, que autentica
  no master mas pode gerenciar qualquer outro realm da mesma instância. Sem realmDestino,
  consulta o próprio realm da credencial.

  Modo automático (com <realmAlias> no lugar do credAlias): resolve sozinho uma credencial de
  admin do master da mesma instância pra consultar esse realm — menu se houver mais de uma
  candidata, com opção de salvar como padrão.

Criação pontual:
  create-client-role <credAlias|realmAlias> <clientId> <roleName> [descricao]
                                                       Cria uma role num client. Idempotente. Aceita
                                                       também um realmAlias (modo automático acima).

Alteração pontual:
  set-client-attr <credAlias|realmAlias> <clientId> <atributo>=<valor> [<atributo>=<valor> ...] [--apply] [realmDestino]
                                                       Altera atributos de um client. Dry-run por
                                                       padrão (tabela ATRIBUTO|ATUAL|NOVO); só grava
                                                       com --apply (pede confirmação [s/N], a menos
                                                       que KC_ASSUME_YES=1). <atributo>=@unset ou
                                                       <atributo>= remove o atributo.

Espelhamento entre ambientes (idempotente — seguro rodar de novo; origem/destino aceitam
também um realmAlias no lugar do credAlias — modo automático acima, útil quando não há
credencial com permissão de realm-management no ambiente):
  mirror-client-roles <sourceCredAlias|realmAlias> <targetCredAlias|realmAlias> <clientIdName>
                                                       Cria no destino as roles que existem na origem e faltam nele.
  mirror-group-roles <sourceCredAlias|realmAlias> <targetCredAlias|realmAlias> <groupPath> <clientIdName> [--recursive]
                                                       Espelha client-role-mappings de um group. Cria o group se faltar.
                                                       --recursive aplica também aos subgrupos.

Exemplos:
  kc setup-realm
  kc setup-client
  kc client-roles sesrj-dev-biae biae
  kc set-client-attr sesrj-dev-biae biae client.session.idle.timeout=7200
  kc mirror-client-roles sesrj-dev-biae sesrj-stg-biae biae
  kc mirror-group-roles sesrj-dev-biae sesrj-stg-biae "/Biae" biae --recursive

  # Modo automático: passe o REALM em vez do credAlias em list-clients/client-roles/
  # realm-roles/list-groups/group-detail/create-client-role/mirror-client-roles/
  # mirror-group-roles — resolve sozinho uma credencial de admin do 'master' da mesma
  # instância (menu se houver mais de uma, com opção de salvar padrão). Útil quando o
  # client do ambiente (ex: service account de prod) não tem permissão de realm-management.
  kc list-clients sesrj-dev
  kc client-roles sesrj-dev biae
  kc mirror-client-roles sesrj-dev ses-rj biae
  kc mirror-group-roles sesrj-dev ses-rj "/Biae" biae --recursive

Ordem recomendada ao cadastrar um ambiente novo: setup-realm (uma vez) -> setup-client (um por
client desse realm) — o client não repete base URL/realm, só referencia o realm pelo alias.

Ordem recomendada ao espelhar um client completo: mirror-client-roles antes de mirror-group-roles
(as roles precisam existir no destino antes de mapeá-las nos groups).
EOF
}

SUBCOMMAND="${1:-}"
[ -n "$SUBCOMMAND" ] && shift || true

case "$SUBCOMMAND" in
  setup-realm)           exec "$SCRIPT_DIR/setup-realm.sh" "$@" ;;
  setup-client)          exec "$SCRIPT_DIR/setup-client.sh" "$@" ;;
  setup-user)            exec "$SCRIPT_DIR/setup-user.sh" "$@" ;;
  delete-client)         exec "$SCRIPT_DIR/kc-delete-client.sh" "$@" ;;
  delete-user)           exec "$SCRIPT_DIR/kc-delete-user.sh" "$@" ;;
  list-realms)           exec "$SCRIPT_DIR/kc-list-realms.sh" "$@" ;;
  list-clients-config)   exec "$SCRIPT_DIR/kc-list-clients-config.sh" "$@" ;;
  list-users-config)     exec "$SCRIPT_DIR/kc-list-users-config.sh" "$@" ;;
  token)                 exec "$SCRIPT_DIR/kc-token.sh" "$@" ;;
  list-clients)          exec "$SCRIPT_DIR/kc-list-clients.sh" "$@" ;;
  realm-roles)           exec "$SCRIPT_DIR/kc-realm-roles.sh" "$@" ;;
  list-groups)           exec "$SCRIPT_DIR/kc-list-groups.sh" "$@" ;;
  group-detail)          exec "$SCRIPT_DIR/kc-group-detail.sh" "$@" ;;
  client-roles)          exec "$SCRIPT_DIR/kc-client-roles.sh" "$@" ;;
  create-client-role)    exec "$SCRIPT_DIR/kc-create-client-role.sh" "$@" ;;
  set-client-attr)       exec "$SCRIPT_DIR/kc-set-client-attr.sh" "$@" ;;
  mirror-client-roles)   exec "$SCRIPT_DIR/kc-mirror-client-roles.sh" "$@" ;;
  mirror-group-roles)    exec "$SCRIPT_DIR/kc-mirror-group-roles.sh" "$@" ;;
  ""|-h|--help|help)     usage; exit 0 ;;
  *)
    echo "Subcomando desconhecido: $SUBCOMMAND" >&2
    echo >&2
    usage
    exit 1
    ;;
esac
