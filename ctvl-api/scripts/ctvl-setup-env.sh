#!/usr/bin/env bash
set -euo pipefail
CTVLCMD_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=lib-ctvl.sh
source "$CTVLCMD_DIR/lib-ctvl.sh"
# Cadastra/edita um ambiente no arquivo de credenciais (modo 600, FORA do git). Interativo:
# a senha é lida com eco mascarado (*) e nunca aparece em argumento, histórico nem saída.
# Uso: ctvl-setup-env.sh <ambiente>      (rodar num terminal, ou no Claude Code com o prefixo !)
if [ "$#" -ne 1 ]; then
  sed -n '2,4p' "${BASH_SOURCE[0]}" >&2
  exit 2
fi
alias_="$1"
if ! [[ "$alias_" =~ ^[a-z][a-z0-9_-]{0,30}$ ]]; then
  ctvl_die "apelido inválido (minúsculas/dígitos, ex.: dev, hml, prd)"
fi
ctvl_check_alias_collision "$alias_"
if [ ! -t 0 ]; then
  ctvl_die "este comando é interativo (precisa de terminal); a senha não pode vir por pipe/argumento"
fi
read -rp "Host do vault (só host[:porta], sem https://): " host
read -rp "Usuário ADMIN do vault: " user
pass="$(ctvl_read_secret_masked 'Senha ADMIN (digite/cole; aparece como *): ')"
read -rp "CA bundle (caminho; Enter = CAs do sistema): " ca
insecure=0
if ctvl_insecure_allowed "$alias_"; then
  read -rp "Desativar verificação TLS neste ambiente? [s/N] " yn
  case "$yn" in [sS] | [sS][iI][mM]) insecure=1 ;; esac
fi
read -rp "Base da API admin [/api] (A CONFIRMAR no seu ambiente): " base
base="${base:-/api}"
if ! [[ "$host" =~ ^[A-Za-z0-9._-]+(:[0-9]{1,5})?$ ]] || [ -z "$user" ] || [ -z "$pass" ]; then
  ctvl_die "host/usuário/senha inválidos ou vazios"
fi
dir="$(dirname "$CTVLAPI_CRED_FILE")"
mkdir -p "$dir"
chmod 700 "$dir"
tmp="$(mktemp "$dir/.credentials.XXXXXX")"
tier=""
if [ -f "$CTVLAPI_CRED_FILE" ]; then
  tier="$(ctvl_cred_get "$alias_" TIER)"
  grep -v "^${alias_}\." "$CTVLAPI_CRED_FILE" >"$tmp" || true
fi
{
  printf '%s.HOST=%s\n' "$alias_" "$host"
  printf '%s.ADMIN_USER=%s\n' "$alias_" "$user"
  printf '%s.ADMIN_PASSWORD=%s\n' "$alias_" "$pass"
  printf '%s.ADMIN_BASE_PATH=%s\n' "$alias_" "$base"
  if [ -n "$ca" ]; then printf '%s.CA_BUNDLE=%s\n' "$alias_" "$ca"; fi
  if [ "$insecure" = "1" ]; then printf '%s.INSECURE_TLS=1\n' "$alias_"; fi
  if [ -n "$tier" ]; then printf '%s.TIER=%s\n' "$alias_" "$tier"; fi
} >>"$tmp"
chmod 600 "$tmp"
mv "$tmp" "$CTVLAPI_CRED_FILE"
# host/usuário podem ter mudado: o JWT em cache do apelido não vale mais (nunca é reenviado a outro host)
rm -f "$CTVLAPI_CACHE_DIR/${alias_}.jwt" "$CTVLAPI_CACHE_DIR/${alias_}.jwt.bind"
printf 'ambiente %s gravado em %s (modo 600). Senha: %s caracteres (não exibida).\n' "$alias_" "$CTVLAPI_CRED_FILE" "${#pass}"
