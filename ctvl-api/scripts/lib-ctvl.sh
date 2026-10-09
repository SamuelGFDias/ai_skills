#!/usr/bin/env bash
# lib-ctvl.sh — funções compartilhadas pelos scripts ctvl-*.sh. Sempre SOURCED, nunca executado.
#
# Modelo de credenciais (fora do git, modo 600), arquivo ~/.config/ai/ctvl/credentials:
#   <apelido>.HOST=<host>                 # só o host, sem https://
#   <apelido>.ADMIN_USER=<usuário admin>
#   <apelido>.ADMIN_PASSWORD=<senha admin>  # alternativa: variável CTVL_ADMIN_PASSWORD_<APELIDO> (maiúsculas, - vira _)
#   <apelido>.CA_BUNDLE=<caminho do bundle> # opcional
#   <apelido>.INSECURE_TLS=0|1              # opcional; só nos apelidos dev, hml, fake ou com TIER=nonprod
#   <apelido>.TIER=nonprod|prod             # opcional; nonprod libera INSECURE_TLS num apelido fora da lista
#   <apelido>.ADMIN_BASE_PATH=/api          # opcional (A CONFIRMAR por ambiente)
#   <apelido>.DATA_BASE_PATH=/vts/rest/v2.0 # opcional (API de dados, usada em verify-mask)
#
# O arquivo é lido linha a linha com split no primeiro "=": nunca é "sourceado", então nada ali é
# executado. Senha e JWT nunca vão em argumento de linha de comando, nunca são impressos.
# Convenção anti-colisão (skill bash-scripting-pitfalls): tudo aqui usa o prefixo CTVLAPI_/ctvl_.

CTVLAPI_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTVLAPI_CORE="$CTVLAPI_LIB_DIR/ctvl_core.py"
CTVLAPI_CRED_FILE="${CTVL_CREDENTIALS_FILE:-$HOME/.config/ai/ctvl/credentials}"
CTVLAPI_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/ctvl-api"
CTVLAPI_TOKEN_FILE=""
CTVLAPI_ALIAS=""

umask 077

ctvl_die() {
  printf 'ERRO: %s\n' "$*" >&2
  exit 1
}

ctvl_need_python() {
  command -v python3 >/dev/null 2>&1 || ctvl_die "python3 não encontrado (necessário para HTTP/YAML)"
  if ! python3 -c 'import yaml' 2>/dev/null; then
    ctvl_die "PyYAML ausente: instale o pacote do sistema (ex.: python3-pyyaml) ou 'pip install --user pyyaml'"
  fi
}

# Imprime o valor de <apelido>.<CAMPO> (vazio se ausente). Última ocorrência vence.
ctvl_cred_get() {
  local alias="$1" field="$2" line key value result=""
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      '' | '#'*) continue ;;
    esac
    key="${line%%=*}"
    value="${line#*=}"
    if [ "$key" = "${alias}.${field}" ]; then
      result="$value"
    fi
  done <"$CTVLAPI_CRED_FILE"
  printf '%s' "$result"
}

ctvl_check_cred_file() {
  if [ ! -f "$CTVLAPI_CRED_FILE" ]; then
    ctvl_die "arquivo de credenciais não encontrado: $CTVLAPI_CRED_FILE (rode 'ctvl.sh setup-env <ambiente>' ou copie credentials.example e use chmod 600)"
  fi
  local mode owner
  mode="$(stat -c '%a' "$CTVLAPI_CRED_FILE")"
  owner="$(stat -c '%u' "$CTVLAPI_CRED_FILE")"
  if [ "$mode" != "600" ]; then
    ctvl_die "permissões inseguras ($mode) em $CTVLAPI_CRED_FILE: rode chmod 600"
  fi
  if [ "$owner" != "$(id -u)" ]; then
    ctvl_die "$CTVLAPI_CRED_FILE não pertence ao usuário atual"
  fi
}

# Recusa o apelido se OUTRO apelido do arquivo normalizar para o mesmo nome de variável de senha
# (x-y e x_y dariam a mesma CTVL_ADMIN_PASSWORD_X_Y e uma senha valeria para os dois ambientes).
ctvl_check_alias_collision() {
  local alias="$1" norm other onorm
  if [ ! -r "$CTVLAPI_CRED_FILE" ]; then
    return 0
  fi
  norm="${alias^^}"
  norm="${norm//-/_}"
  while IFS= read -r other; do
    if [ "$other" = "$alias" ]; then
      continue
    fi
    onorm="${other^^}"
    onorm="${onorm//-/_}"
    if [ "$onorm" = "$norm" ]; then
      ctvl_die "apelidos '$alias' e '$other' colidem na variável de senha CTVL_ADMIN_PASSWORD_$norm: renomeie um deles em $CTVLAPI_CRED_FILE"
    fi
  done < <(sed -n 's/^\([a-z][a-z0-9_-]*\)\.[A-Z_]*=.*/\1/p' "$CTVLAPI_CRED_FILE" | sort -u)
}

# Carrega host/TLS/paths do ambiente <apelido> (sem ler a senha). Define variáveis CTVLAPI_*.
ctvl_load_env() {
  local alias="$1"
  if ! [[ "$alias" =~ ^[a-z][a-z0-9_-]{0,30}$ ]]; then
    ctvl_die "apelido de ambiente inválido '$alias' (use minúsculas/dígitos, ex.: dev, hml, prd)"
  fi
  ctvl_need_python
  ctvl_check_cred_file
  ctvl_check_alias_collision "$alias"
  CTVLAPI_ALIAS="$alias"
  CTVLAPI_HOST="$(ctvl_cred_get "$alias" HOST)"
  if [ -z "$CTVLAPI_HOST" ]; then
    ctvl_die "ambiente '$alias' sem HOST em $CTVLAPI_CRED_FILE (veja credentials.example)"
  fi
  if ! [[ "$CTVLAPI_HOST" =~ ^[A-Za-z0-9._-]+(:[0-9]{1,5})?$ ]]; then
    ctvl_die "HOST de '$alias' inválido: informe só host[:porta], sem esquema nem caminho"
  fi
  CTVLAPI_SCHEME="$(ctvl_cred_get "$alias" SCHEME)"
  CTVLAPI_SCHEME="${CTVLAPI_SCHEME:-https}"
  case "$CTVLAPI_SCHEME" in
    https) ;;
    http)
      case "$CTVLAPI_HOST" in
        127.0.0.1 | 127.0.0.1:* | localhost | localhost:*) ;;
        *) ctvl_die "SCHEME=http só é aceito para loopback (testes com servidor falso)" ;;
      esac
      ;;
    *) ctvl_die "SCHEME de '$alias' inválido (https; http só em loopback)" ;;
  esac
  CTVLAPI_ADMIN_BASE="$(ctvl_cred_get "$alias" ADMIN_BASE_PATH)"
  CTVLAPI_ADMIN_BASE="${CTVLAPI_ADMIN_BASE:-/api}"
  CTVLAPI_DATA_BASE="$(ctvl_cred_get "$alias" DATA_BASE_PATH)"
  CTVLAPI_DATA_BASE="${CTVLAPI_DATA_BASE:-/vts/rest/v2.0}"
  if ! [[ "$CTVLAPI_ADMIN_BASE" =~ ^/[A-Za-z0-9/_.-]*$ ]] || ! [[ "$CTVLAPI_DATA_BASE" =~ ^/[A-Za-z0-9/_.-]*$ ]]; then
    ctvl_die "ADMIN_BASE_PATH/DATA_BASE_PATH inválidos em '$alias'"
  fi
  CTVLAPI_CA="$(ctvl_cred_get "$alias" CA_BUNDLE)"
  if [ -n "$CTVLAPI_CA" ] && [ ! -r "$CTVLAPI_CA" ]; then
    ctvl_die "CA_BUNDLE de '$alias' não é legível: $CTVLAPI_CA"
  fi
  CTVLAPI_INSECURE="$(ctvl_cred_get "$alias" INSECURE_TLS)"
  CTVLAPI_INSECURE="${CTVLAPI_INSECURE:-0}"
  if [ "$CTVLAPI_INSECURE" != "0" ] && [ "$CTVLAPI_INSECURE" != "1" ]; then
    ctvl_die "INSECURE_TLS de '$alias' deve ser 0 ou 1"
  fi
  case "$(ctvl_cred_get "$alias" TIER)" in
    '' | prod | nonprod) ;;
    *) ctvl_die "TIER de '$alias' deve ser nonprod ou prod" ;;
  esac
  if [ "$CTVLAPI_INSECURE" = "1" ] && ! ctvl_insecure_allowed "$alias"; then
    ctvl_die "TLS inseguro é proibido no ambiente $alias (só nos apelidos dev, hml e fake, ou com $alias.TIER=nonprod no arquivo de credenciais)"
  fi
}

# 0 se INSECURE_TLS pode ser usado no apelido: lista explícita (dev, hml, fake) ou <apelido>.TIER=nonprod.
# Qualquer outro nome (prd, prod, producao, prd2...) é recusado; TIER=prod recusa até dev/hml.
ctvl_insecure_allowed() {
  local alias="$1" tier=""
  if [ -r "$CTVLAPI_CRED_FILE" ]; then
    tier="$(ctvl_cred_get "$alias" TIER)"
  fi
  case "$tier" in
    prod) return 1 ;;
    nonprod) return 0 ;;
  esac
  case "$alias" in
    dev | hml | fake) return 0 ;;
  esac
  return 1
}

# Variáveis CTVL_ADMIN_PASSWORD* do ambiente do processo são removidas (env -u) antes de chamar o motor
# Python: ele nunca precisa delas (o login leva a senha por CTVL_LOGIN_*) e assim password_ref não as lê.
ctvl_scrub_args() {
  CTVLAPI_SCRUB=()
  local v
  while IFS= read -r v; do
    case "$v" in
      CTVL_ADMIN_PASSWORD*) CTVLAPI_SCRUB+=(-u "$v") ;;
    esac
  done < <(compgen -e)
}

# Executa o motor Python com a conexão do ambiente carregado. Segredos NÃO passam por aqui:
# o token vai por arquivo (CTVL_TOKEN_FILE); a senha só no login, via variável de ambiente do filho.
ctvl_py_conn() {
  ctvl_scrub_args
  env ${CTVLAPI_SCRUB[@]+"${CTVLAPI_SCRUB[@]}"} \
    CTVL_CONN_SCHEME="$CTVLAPI_SCHEME" CTVL_CONN_HOST="$CTVLAPI_HOST" CTVL_CONN_BASE="$CTVLAPI_ADMIN_BASE" \
    CTVL_CONN_DATA_BASE="$CTVLAPI_DATA_BASE" CTVL_CONN_CA="$CTVLAPI_CA" CTVL_CONN_INSECURE="$CTVLAPI_INSECURE" \
    CTVL_HOST_MASK="$CTVLAPI_HOST" CTVL_ALIAS="$CTVLAPI_ALIAS" CTVL_TOKEN_FILE="$CTVLAPI_TOKEN_FILE" \
    python3 -B "$CTVLAPI_CORE" "$@"
}

# Nome da variável com a senha admin DO ambiente carregado: CTVL_ADMIN_PASSWORD_<APELIDO> (maiúsculas, - vira _).
# A variável global CTVL_ADMIN_PASSWORD valia para todos os ambientes e foi aposentada.
ctvl_admin_pass_var() {
  local a="${CTVLAPI_ALIAS^^}"
  printf 'CTVL_ADMIN_PASSWORD_%s' "${a//-/_}"
}

# Hash que prende o JWT em cache ao ambiente (apelido, esquema, host, base e usuário admin).
# Nunca grava o host em claro: o cache de um host antigo não é reenviado a um host novo.
ctvl_cache_bind() {
  local user
  user="$(ctvl_cred_get "$CTVLAPI_ALIAS" ADMIN_USER)"
  printf '%s\n%s\n%s\n%s\n%s\n' "$CTVLAPI_ALIAS" "$CTVLAPI_SCHEME" "$CTVLAPI_HOST" "$CTVLAPI_ADMIN_BASE" "$user" |
    python3 -B -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())'
}

# 0 se há JWT em cache emitido para o host+usuário atuais; senão 1 (cache legado sem selo também é recusado).
ctvl_cache_ok() {
  local tf="$CTVLAPI_CACHE_DIR/${CTVLAPI_ALIAS}.jwt" want have
  if [ ! -f "$tf" ] || [ ! -f "$tf.bind" ]; then
    return 1
  fi
  want="$(ctvl_cache_bind)"
  have="$(cat "$tf.bind" 2>/dev/null || true)"
  if [ "$want" = "$have" ]; then
    return 0
  fi
  return 1
}

ctvl_login() {
  local user pass pvar tf="$CTVLAPI_CACHE_DIR/${CTVLAPI_ALIAS}.jwt"
  user="$(ctvl_cred_get "$CTVLAPI_ALIAS" ADMIN_USER)"
  pvar="$(ctvl_admin_pass_var)"
  if [ -n "${CTVL_ADMIN_PASSWORD+x}" ]; then
    printf 'AVISO: a variável global CTVL_ADMIN_PASSWORD foi aposentada e é IGNORADA (valia para todos os ambientes). Use %s.\n' "$pvar" >&2
  fi
  pass="${!pvar:-}"
  if [ -z "$pass" ]; then
    pass="$(ctvl_cred_get "$CTVLAPI_ALIAS" ADMIN_PASSWORD)"
  fi
  if [ -z "$user" ] || [ -z "$pass" ]; then
    ctvl_die "credencial ADMIN do ambiente '$CTVLAPI_ALIAS' ausente. A credencial admin precisa ser fornecida pelo usuário (arquivo de credenciais ou variável $pvar). NÃO use credencial de tokenize/detokenize na API admin."
  fi
  CTVLAPI_TOKEN_FILE=""
  rm -f "$tf" "$tf.bind"
  CTVL_LOGIN_USER="$user" CTVL_LOGIN_PASSWORD="$pass" ctvl_py_conn login --out "$tf"
  ctvl_cache_bind >"$tf.bind"
  chmod 600 "$tf.bind"
  CTVLAPI_TOKEN_FILE="$tf"
}

# Garante um JWT válido em cache (modo 600). --refresh força novo login. Nunca imprime o token.
ctvl_ensure_token() {
  local force="${1:-}" tf ttl
  mkdir -p "$CTVLAPI_CACHE_DIR"
  chmod 700 "$CTVLAPI_CACHE_DIR"
  tf="$CTVLAPI_CACHE_DIR/${CTVLAPI_ALIAS}.jwt"
  if [ "$force" != "--refresh" ] && ctvl_cache_ok; then
    ttl="$(python3 -B "$CTVLAPI_CORE" jwt-ttl "$tf" 2>/dev/null || echo 0)"
    if [ "${ttl:-0}" -gt 60 ]; then
      CTVLAPI_TOKEN_FILE="$tf"
      return 0
    fi
  fi
  ctvl_login
}

# Roda um subcomando do motor com token; num 401 (rc 77) renova o token e repete uma vez.
ctvl_run() {
  ctvl_ensure_token
  local rc=0
  ctvl_py_conn "$@" || rc=$?
  if [ "$rc" -eq 77 ]; then
    printf '[ctvl] token rejeitado; renovando e repetindo uma vez.\n' >&2
    ctvl_ensure_token --refresh
    rc=0
    ctvl_py_conn "$@" || rc=$?
  fi
  return "$rc"
}

# Uso: ctvl_dispatch <ambiente|--offline> <subcomando> [args...]
ctvl_dispatch() {
  local first="${1:-}"
  if [ -z "$first" ]; then
    ctvl_die "faltou o ambiente (dev|hml|prd) ou --offline"
  fi
  shift
  if [ "$first" = "--offline" ]; then
    ctvl_need_python
    ctvl_scrub_args
    env ${CTVLAPI_SCRUB[@]+"${CTVLAPI_SCRUB[@]}"} CTVL_ALIAS="offline" python3 -B "$CTVLAPI_CORE" "$@"
  else
    ctvl_load_env "$first"
    ctvl_run "$@"
  fi
}

# Lê um segredo sem ecoar: cada caractere vira "*" (mesma ideia da skill keycloak-api).
ctvl_read_secret_masked() {
  local prompt="$1" secret="" char
  printf '%s' "$prompt" >&2
  while IFS= read -r -s -n 1 char; do
    if [ -z "$char" ]; then
      break
    fi
    if [ "$char" = $'\x7f' ] || [ "$char" = $'\x08' ]; then
      if [ -n "$secret" ]; then
        secret="${secret%?}"
        printf '\b \b' >&2
      fi
      continue
    fi
    secret+="$char"
    printf '*' >&2
  done
  printf '\n' >&2
  printf '%s' "$secret"
}
