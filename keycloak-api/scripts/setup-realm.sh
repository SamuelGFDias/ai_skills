#!/usr/bin/env bash
# Cadastra ou edita um realm Keycloak (base URL + nome técnico do realm).
# Um realm cadastrado aqui pode ser reutilizado por vários clients/users (kc setup-client,
# kc setup-user), sem repetir base URL/realm a cada credencial do mesmo ambiente.
#
# Pode ser salvo em dois lugares:
#   local  -> ~/.claude/secrets/keycloak/realms/  (só nesta máquina, não versionado)
#   equipe -> keycloak-api/realms/ no repo da skill (versionado, some para o time inteiro
#             ao dar git commit/push — não vai secret nenhum aqui, só base URL + nome)
# Local tem prioridade sobre equipe quando o mesmo alias existe nos dois (override pessoal).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-env.sh
source "$SCRIPT_DIR/lib-env.sh"

mkdir -p "$REALMS_DIR"
chmod 700 "$SECRETS_ROOT" "$REALMS_DIR"

mapfile -t EXISTING < <(list_realm_aliases)
if [ "${#EXISTING[@]}" -gt 0 ]; then
  echo "Realms disponíveis hoje: ${EXISTING[*]}" >&2
  echo "(informe um desses alias abaixo para editar, ou um novo nome para cadastrar)" >&2
  echo >&2
fi

REALM_ALIAS="$(read_required "Alias para este realm (ex: sesrj-dev): ")"

echo >&2
echo "Onde salvar?" >&2
PS3="Destino> "
SAVE_TARGET=""
select opt in "local (só esta máquina)" "equipe (versionado no repo da skill, some pro time)"; do
  case "$REPLY" in
    1) SAVE_TARGET="local"; break ;;
    2) SAVE_TARGET="team"; break ;;
    *) echo "Opção inválida, escolha 1 ou 2." >&2 ;;
  esac
done

if [ "$SAVE_TARGET" = "local" ]; then
  ENV_FILE="$REALMS_DIR/${REALM_ALIAS}.env"
else
  mkdir -p "$TEAM_REALMS_DIR"
  ENV_FILE="$TEAM_REALMS_DIR/${REALM_ALIAS}.env"
fi

KEYCLOAK_BASE_URL=""
KEYCLOAK_REALM=""
PREFILL_SOURCE="$(resolve_realm_env_file "$REALM_ALIAS")"
if [ -n "$PREFILL_SOURCE" ]; then
  echo "Já existe cadastro para '${REALM_ALIAS}' (origem: $(realm_origin "$REALM_ALIAS")) — Enter mantém o valor atual." >&2
  load_env_file_safe "$PREFILL_SOURCE" KEYCLOAK_BASE_URL KEYCLOAK_REALM
fi

BASE_URL="$(read_required_default "Base URL do Keycloak (ex: https://sso-dev.saude.rj.gov.br)" "$KEYCLOAK_BASE_URL")"
REALM="$(read_required_default "Nome técnico do realm no Keycloak (ex: sesrj-dev)" "$KEYCLOAK_REALM")"

cat > "$ENV_FILE" <<EOF
KEYCLOAK_BASE_URL=${BASE_URL}
KEYCLOAK_REALM=${REALM}
EOF

if [ "$SAVE_TARGET" = "local" ]; then
  chmod 600 "$ENV_FILE"
fi

echo
echo "Realm salvo ($SAVE_TARGET): $REALM_ALIAS"
echo "  Base URL: $BASE_URL"
echo "  Realm:    $REALM"
echo "  Arquivo:  $ENV_FILE"
if [ "$SAVE_TARGET" = "team" ]; then
  echo
  echo "Lembrete: isso não é secret, mas ainda precisa de 'git add/commit/push' no repo da"
  echo "skill (~/.config/ai/skills) pra chegar ao resto da equipe — este script não commita."
fi
echo
echo "Próximo passo: kc setup-client (associa um client a este realm)."
