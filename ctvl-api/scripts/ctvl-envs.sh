#!/usr/bin/env bash
set -euo pipefail
CTVLCMD_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=lib-ctvl.sh
source "$CTVLCMD_DIR/lib-ctvl.sh"
# Lista os ambientes cadastrados e o que está configurado (sem mostrar host, usuário nem senha).
# Uso: ctvl-envs.sh
ctvl_check_cred_file
mapfile -t aliases < <(sed -n 's/^\([a-z][a-z0-9_-]*\)\.[A-Z_]*=.*/\1/p' "$CTVLAPI_CRED_FILE" | sort -u)
if [ "${#aliases[@]}" -eq 0 ]; then
  echo "nenhum ambiente em $CTVLAPI_CRED_FILE"
  exit 0
fi
printf '%-9s %-9s %-11s %-12s %-13s %s\n' AMBIENTE HOST ADMIN_USER ADMIN_SENHA TLS_INSEGURO CA_BUNDLE
for a in "${aliases[@]}"; do
  h="$(ctvl_cred_get "$a" HOST)"
  u="$(ctvl_cred_get "$a" ADMIN_USER)"
  p="$(ctvl_cred_get "$a" ADMIN_PASSWORD)"
  i="$(ctvl_cred_get "$a" INSECURE_TLS)"
  c="$(ctvl_cred_get "$a" CA_BUNDLE)"
  printf '%-9s %-9s %-11s %-12s %-13s %s\n' "$a" "${h:+definido}" "${u:+definido}" "${p:+definida}" "${i:-0}" "${c:+definido}"
done
