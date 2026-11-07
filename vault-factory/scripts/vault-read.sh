#!/usr/bin/env bash
# vault-read <ref> — despachante de leitura de segredo por referência com esquema.
# Escreve o valor em stdout, sem quebra de linha final, e mais nada. Contrato em docs/contrato-provider.md.
# Códigos de saída: 0 ok | 1 falha de leitura ou valor vazio | 2 esquema ausente/desconhecido | 3 CLI ausente.
set -euo pipefail

usage() {
  printf '%s\n' \
    'Uso: vault-read <ref>' \
    '' \
    'Esquemas aceitos:' \
    '  op://<cofre>/<item>/<campo>       1Password' \
    '  pass:<caminho>                    pass' \
    '  gopass:<caminho>                  gopass' \
    '  passbolt:<id-ou-nome>[#campo]     Passbolt (campo: password padrão, description, username, uri)' \
    '  passbolt://<id-ou-nome>[#campo]   Passbolt (sinônimo de passbolt:)' \
    '  vault:<mount>/<caminho>#<chave>   HashiCorp Vault (KV v2)' >&2
}

# Mensagens de erro citam só o esquema e o motivo, nunca o valor nem o caminho do segredo.
die() {
  local code="$1"
  shift
  echo "vault-read: $*" >&2
  exit "$code"
}

# require_cli <comando> <provider> <esquema>
require_cli() {
  command -v "$1" >/dev/null 2>&1 \
    || die 3 "esquema $3: CLI '$1' ausente; ver providers/$2/runbook-linux.md"
}

# emit <esquema> <valor>: valor vazio é falha; senão escreve sem newline final.
emit() {
  [ -n "$2" ] || die 1 "esquema $1: valor vazio"
  printf '%s' "$2"
}

# rejeita_traco <esquema> <valor>: valor iniciado em '-' seria lido como flag pelo CLI.
rejeita_traco() {
  case "$2" in
    -*) die 2 "esquema $1: referência inválida" ;;
  esac
}

# token_state <arquivo>: ausente (não legível) | vazio (vazio, só \r\n ou diretório) | ok. Não imprime o conteúdo.
token_state() {
  if [ -d "$1" ]; then
    echo vazio
  elif [ ! -r "$1" ]; then
    echo ausente
  elif [ -z "$(tr -d '\r\n' < "$1" 2>/dev/null | head -c1)" ]; then
    echo vazio
  else
    echo ok
  fi
}

# acha_op_sa: caminho do op-sa — no PATH ou, senão, o irmão deste script (resolvendo symlinks).
acha_op_sa() {
  local self here
  if command -v op-sa >/dev/null 2>&1; then
    command -v op-sa
    return 0
  fi
  self="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null)" || return 1
  here="$(dirname "$self")"
  [ -x "$here/op-sa" ] || return 1
  echo "$here/op-sa"
}

read_op() {
  local ref="$1" cli val tok_file tok body seg1 seg2 seg3
  # op:// exige <cofre>/<item>/<campo>; referência de item inteiro não é segredo.
  body="${ref#op://}"
  body="${body%%\?*}"
  IFS=/ read -r seg1 seg2 seg3 _ <<<"$body"
  { [ -n "$seg1" ] && [ -n "$seg2" ] && [ -n "$seg3" ]; } \
    || die 2 "esquema op://: referência inválida; formato op://<cofre>/<item>/<campo>"
  # O estado do token vale independentemente de onde está o op-sa: existente porém vazio é erro,
  # nunca motivo de fallback para a sessão pessoal. Sem token (inexistente/ilegível) usa o `op` direto.
  cli="op"
  tok_file="${OP_SA_TOKEN_FILE:-$HOME/.config/op/service-account-token}"
  tok="$(token_state "$tok_file")"
  case "$tok" in
    vazio) die 1 "esquema op://: token do service account vazio" ;;
    ok) cli="$(acha_op_sa)" || cli="op" ;;
  esac
  require_cli "$cli" 1password "op://"
  # op-sa delega ao `op`; sem ele a falha seria de execução, não de CLI ausente.
  [ "$cli" = op ] || require_cli op 1password "op://"
  val="$("$cli" read "$ref" 2>/dev/null)" || die 1 "esquema op://: falha ao ler a referência"
  emit "op://" "$val"
}

read_pass() {
  local path="$1" out val store
  [ -n "$path" ] || die 2 "esquema pass: caminho vazio"
  rejeita_traco pass "$path"
  require_cli pass pass-gopass "pass"
  # O alvo tem de ser arquivo do store; `pass show` de diretório imprime a árvore.
  store="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
  case "/$path/" in
    */../*) die 2 "esquema pass: referência inválida" ;;
  esac
  [ -f "$store/$path.gpg" ] || die 1 "esquema pass: entrada inexistente no store"
  out="$(pass show -- "$path" 2>/dev/null)" || die 1 "esquema pass: falha ao ler o caminho"
  val="${out%%$'\n'*}"
  emit "pass" "${val%$'\r'}"
}

read_gopass() {
  local path="$1" val
  [ -n "$path" ] || die 2 "esquema gopass: caminho vazio"
  rejeita_traco gopass "$path"
  require_cli gopass pass-gopass "gopass"
  val="$(gopass show -o "$path" 2>/dev/null)" || die 1 "esquema gopass: falha ao ler o caminho"
  emit "gopass" "$val"
}

read_passbolt() {
  local query="$1" campo=password here rid json val
  case "$query" in
    *#*) campo="${query##*#}"; query="${query%#*}" ;;
  esac
  [ -n "$query" ] || die 2 "esquema passbolt: identificador vazio"
  rejeita_traco passbolt "$query"
  case "$campo" in
    password|description|username|uri) ;;
    *) die 2 "esquema passbolt: campo inválido; use #password, #description, #username ou #uri" ;;
  esac
  require_cli passbolt passbolt "passbolt"
  require_cli jq passbolt "passbolt"
  here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
  # shellcheck source=lib.sh
  source "$here/lib.sh"
  # O stderr do resolvedor cita o nome do recurso; descartado para não vazar a referência.
  rid="$(resolve_resource_id "$query" 2>/dev/null)" \
    || die 1 "esquema passbolt: recurso não resolvido (inexistente ou ambíguo)"
  [ -n "$rid" ] || die 1 "esquema passbolt: recurso não resolvido (inexistente ou ambíguo)"
  json="$(passbolt get resource --id "$rid" --json 2>/dev/null)" \
    || die 1 "esquema passbolt: falha ao ler o recurso"
  # Mesma ordem de busca de pb-import.sh (secret, metadata, raiz), com e sem maiúscula inicial.
  val="$(jq -r --arg c "$campo" --arg C "${campo^}" '
      .secret[$c] // .secret[$C] // .Secret[$c] // .Secret[$C] //
      .metadata[$c] // .Metadata[$c] // .[$c] // .[$C] // empty
    ' <<<"$json")" || die 1 "esquema passbolt: resposta ilegível"
  emit "passbolt" "$val"
}

read_vault() {
  local rest="$1" mount path key val
  case "$rest" in
    */*#?*) ;;
    *) die 2 "esquema vault: formato esperado vault:<mount>/<caminho>#<chave>" ;;
  esac
  key="${rest##*#}"
  rest="${rest%#*}"
  mount="${rest%%/*}"
  path="${rest#*/}"
  [ -n "$mount" ] && [ -n "$path" ] \
    || die 2 "esquema vault: formato esperado vault:<mount>/<caminho>#<chave>"
  rejeita_traco vault "$mount"
  rejeita_traco vault "$path"
  rejeita_traco vault "$key"
  require_cli vault vault "vault"
  val="$(vault kv get -mount="$mount" -field="$key" -- "$path" 2>/dev/null)" \
    || die 1 "esquema vault: falha ao ler o segredo"
  # -field de chave que guarda mapa/lista devolve JSON estruturado, não um valor escalar.
  if command -v jq >/dev/null 2>&1 \
    && jq -e 'type == "object" or type == "array"' >/dev/null 2>&1 <<<"$val"; then
    die 1 "esquema vault: a chave não é um valor escalar"
  fi
  emit "vault" "$val"
}

main() {
  local ref="${1:-}"
  if [ -z "$ref" ]; then
    usage
    exit 2
  fi
  case "$ref" in
    op://*) read_op "$ref" ;;
    pass:*) read_pass "${ref#pass:}" ;;
    gopass:*) read_gopass "${ref#gopass:}" ;;
    passbolt://*) read_passbolt "${ref#passbolt://}" ;;
    passbolt:*) read_passbolt "${ref#passbolt:}" ;;
    vault:*) read_vault "${ref#vault:}" ;;
    *)
      usage
      die 2 "esquema desconhecido"
      ;;
  esac
}

main "$@"
