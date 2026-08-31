#!/usr/bin/env bash
# Cadastra ou edita uma credencial de usuário/senha do Cronograma (SES-RJ), usada por
# login.sh. Nunca passe usuário/senha como argumento de linha de comando nem os digite
# na conversa com o assistente — rode este script interativamente.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-secrets.sh
source "$SCRIPT_DIR/lib-secrets.sh"

mkdir -p "$USERS_DIR"
chmod 700 "$SECRETS_ROOT" "$USERS_DIR"

ALIAS="$(read_required_default "Alias para esta credencial (ex: default)" "default")"
ENV_FILE="$USERS_DIR/${ALIAS}.env"

CRONOGRAMA_USERNAME=""
CRONOGRAMA_PASSWORD=""
EDITING=0
if [ -f "$ENV_FILE" ]; then
  EDITING=1
  load_env_file_safe "$ENV_FILE" CRONOGRAMA_USERNAME CRONOGRAMA_PASSWORD
  echo "Credencial '${ALIAS}' já existe — Enter mantém o valor atual em cada campo abaixo." >&2
fi

USERNAME="$(read_required_default "Username" "$CRONOGRAMA_USERNAME")"

if [ "$EDITING" = "1" ] && [ -n "$CRONOGRAMA_PASSWORD" ]; then
  echo "Senha atual: $(mask_bar "${#CRONOGRAMA_PASSWORD}") (${#CRONOGRAMA_PASSWORD} caracteres)" >&2
  echo "Cole/digite uma nova senha para substituir, ou Enter em branco para manter a atual." >&2
fi
TYPED_PASSWORD="$(read_secret_masked "Password: ")"

if [ -z "$TYPED_PASSWORD" ] && [ "$EDITING" = "1" ] && [ -n "$CRONOGRAMA_PASSWORD" ]; then
  PASSWORD="$CRONOGRAMA_PASSWORD"
else
  PASSWORD="$TYPED_PASSWORD"
  [ -n "$PASSWORD" ] || { echo "Password não pode ficar em branco." >&2; exit 1; }
fi

cat > "$ENV_FILE" <<EOF
CRONOGRAMA_USERNAME=${USERNAME}
CRONOGRAMA_PASSWORD=${PASSWORD}
EOF
chmod 600 "$ENV_FILE"

echo
echo "Credencial salva: $ALIAS"
echo "  Username: $USERNAME"
echo "  Password: $(mask_bar "${#PASSWORD}") (${#PASSWORD} caracteres — confira se bate com o que você colou)"
echo
echo "Use com: login.sh $ALIAS"
