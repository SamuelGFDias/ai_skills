#!/usr/bin/env bash
# Cria/atualiza um arquivo de credenciais para um "alias" de client Keycloak.
# O valor da secret é lido com `read -s` (não ecoa no terminal) e o script
# NUNCA imprime a secret em stdout/stderr — por isso é seguro rodar via
# o prefixo "!" dentro do Claude Code sem que o valor apareça na conversa.
set -euo pipefail

SECRETS_DIR="$HOME/.claude/secrets/keycloak"
mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

# Repete a pergunta até vir um valor não-vazio — evita salvar campo em
# branco silenciosamente (o que já aconteceu: script dizia "sucesso" com
# campo vazio porque não havia validação nenhuma).
read_required() {
  local prompt="$1"
  local value=""
  while [ -z "$value" ]; do
    read -rp "$prompt" value
    [ -z "$value" ] && echo "  -> não pode ficar vazio, tente de novo." >&2
  done
  printf '%s' "$value"
}

read_required_silent() {
  local prompt="$1"
  local value=""
  while [ -z "$value" ]; do
    read -rsp "$prompt" value
    echo >&2
    [ -z "$value" ] && echo "  -> não pode ficar vazio, tente de novo." >&2
  done
  printf '%s' "$value"
}

ALIAS="$(read_required "Alias para esta credencial (ex: realm-dev-meu-app): ")"
BASE_URL="$(read_required "Base URL do Keycloak (ex: https://sso-dev.example.com): ")"
REALM="$(read_required "Realm (ex: realm-dev): ")"
CLIENT_ID="$(read_required "Client ID (ex: meu-app): ")"
CLIENT_SECRET="$(read_required_silent "Client Secret (não será exibido): ")"

ENV_FILE="$SECRETS_DIR/${ALIAS}.env"

cat > "$ENV_FILE" <<EOF
KEYCLOAK_BASE_URL=${BASE_URL}
KEYCLOAK_REALM=${REALM}
KEYCLOAK_CLIENT_ID=${CLIENT_ID}
KEYCLOAK_CLIENT_SECRET=${CLIENT_SECRET}
EOF

chmod 600 "$ENV_FILE"

echo "Credenciais salvas em: $ENV_FILE (permissão 600)"
echo "Alias: $ALIAS"
echo "Conferência (tamanho em caracteres, não o valor):"
echo "  BASE_URL: ${#BASE_URL}"
echo "  REALM: ${#REALM}"
echo "  CLIENT_ID: ${#CLIENT_ID}"
echo "  CLIENT_SECRET: ${#CLIENT_SECRET}"
