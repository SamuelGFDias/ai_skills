#!/usr/bin/env bash
# Testa vault-read.sh com stubs dos CLIs dos providers num diretório temporário injetado no PATH.
# Nenhum cofre real é tocado. O "segredo" é um valor sintético gerado a cada execução.
set -uo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
SCRIPT="$HERE/../scripts/vault-read.sh"
BASH_BIN="$(command -v bash)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SECRET="s3gredo-sintetico-$RANDOM$RANDOM"
# campos extras do Passbolt: valores sintéticos distintos da senha, para provar qual campo foi lido
DESC="nota-sintetica-$RANDOM$RANDOM"
USUARIO="usuario-sintetico-$RANDOM$RANDOM"
URI_S="https://sintetico-$RANDOM.invalid"
PASS=0
FAIL=0

ok() { echo "OK     $1"; PASS=$((PASS + 1)); }
falha() { echo "FALHA  $1${2:+ — $2}"; FAIL=$((FAIL + 1)); }

# --- stubs: cada um grava o próprio argv em $ARGV_LOG e devolve $STUB_VALUE ---
STUBS="$TMP/stubs"
mkdir -p "$STUBS"
ARGV_LOG="$TMP/argv.log"

make_stub() { # make_stub <nome> <corpo>
  printf '#!%s\nprintf "%%s\\n" "$0 $*" >> "$ARGV_LOG"\n%s\n' "$BASH_BIN" "$2" > "$STUBS/$1"
  chmod +x "$STUBS/$1"
}
make_stub op 'printf "%s\n" "$STUB_VALUE"'
make_stub op-sa 'printf "%s\n" "$STUB_VALUE"'
make_stub pass 'printf "%s\nlinha-extra\n" "$STUB_VALUE"'
make_stub gopass 'printf "%s\n" "$STUB_VALUE"'
make_stub vault 'printf "%s\n" "$STUB_VALUE"'
make_stub passbolt '
LISTA="$STUB_LIST"
[ -n "$LISTA" ] || LISTA="[{\"id\":\"11111111-2222-3333-4444-555555555555\",\"name\":\"recurso-teste\"}]"
case "$1 $2" in
  "list resources") printf "%s\n" "$LISTA" ;;
  "get resource") printf "{\"secret\":{\"password\":\"%s\",\"description\":\"%s\",\"username\":\"%s\",\"uri\":\"%s\"}}\n" "$STUB_VALUE" "$STUB_DESC" "$STUB_USER" "$STUB_URI" ;;
  *) exit 1 ;;
esac'
# utilitários que o script usa e que não são os CLIs dos providers
for u in jq readlink dirname tr head; do ln -s "$(command -v "$u")" "$STUBS/$u"; done

# store do pass sintético (arquivos .gpg vazios; o stub de pass não os lê) e token file do op-sa
export PASSWORD_STORE_DIR="$TMP/store"
mkdir -p "$PASSWORD_STORE_DIR/dir-sigiloso" "$PASSWORD_STORE_DIR/a/b" "$PASSWORD_STORE_DIR/caminho" "$PASSWORD_STORE_DIR/Business"
for e in a/b/c a/b x caminho/sigiloso Business/conta; do : > "$PASSWORD_STORE_DIR/$e.gpg"; done
TOKFILE_OK="$TMP/tok-ok"; printf 'token-sintetico\n' > "$TOKFILE_OK"

# run <PATH> <ref>: roda o despachante; grava stdout em $TMP/out e stderr em $TMP/err; devolve o exit code
run() {
  : > "$ARGV_LOG"
  env PATH="$1" OP_SA_TOKEN_FILE="${TOKFILE-$TOKFILE_OK}" ARGV_LOG="$ARGV_LOG" STUB_VALUE="${STUB_VALUE-$SECRET}" \
    STUB_DESC="${STUB_DESC-$DESC}" STUB_USER="${STUB_USER-$USUARIO}" STUB_URI="${STUB_URI-$URI_S}" \
    "$BASH_BIN" "$SCRIPT" "${@:2}" \
    > "$TMP/out" 2> "$TMP/err"
}

# path_sem <cli>...: diretório de PATH com os stubs menos os CLIs listados
path_sem() {
  local d="$TMP/path-sem-$*" f skip x
  mkdir -p "$d"
  for f in "$STUBS"/*; do
    skip=0
    for x in "$@"; do [ "$(basename "$f")" = "$x" ] && skip=1; done
    [ "$skip" -eq 0 ] && ln -sf "$f" "$d/$(basename "$f")"
  done
  echo "$d"
}

# confere <descrição> <esquema> <ref> <trecho esperado no argv do stub> [PATH]
confere_despacho() {
  local desc="$1" ref="$2" esperado="$3" p="${4:-$STUBS}"
  if run "$p" "$ref"; then
    local got
    got="$(cat "$TMP/out")"
    if [ "$got" = "$SECRET" ] && grep -qF -- "$esperado" "$ARGV_LOG"; then
      ok "$desc"
    else
      falha "$desc" "valor ou argv inesperado ($(head -c 120 "$ARGV_LOG"))"
    fi
  else
    falha "$desc" "exit != 0"
  fi
}

# --- despacho por esquema ---
confere_despacho "op:// usa op-sa quando existe" "op://cofre/item/campo" "/op-sa read op://cofre/item/campo"
TOKFILE="$TMP/inexistente" confere_despacho "op:// cai para op sem op-sa e sem token" "op://cofre/item/campo" "/op read op://cofre/item/campo" "$(path_sem op-sa)"
confere_despacho "pass: usa pass show" "pass:a/b/c" "/pass show -- a/b/c"
confere_despacho "gopass: usa gopass show -o" "gopass:a/b/c" "/gopass show -o a/b/c"
confere_despacho "passbolt: resolve por UUID" "passbolt:11111111-2222-3333-4444-555555555555" "get resource --id 11111111-2222-3333-4444-555555555555"
confere_despacho "passbolt: resolve por nome" "passbolt:recurso-teste" "get resource --id 11111111-2222-3333-4444-555555555555"
confere_despacho "vault: usa vault kv get" "vault:kv/dir/seg#chave" "/vault kv get -mount=kv -field=chave -- dir/seg"

# confere_valor <descrição> <ref> <valor esperado>: confere o stdout exato
confere_valor() {
  local desc="$1" ref="$2" esperado="$3"
  if run "$STUBS" "$ref" && [ "$(cat "$TMP/out")" = "$esperado" ]; then
    ok "$desc"
  else
    falha "$desc" "valor inesperado"
  fi
}

# --- passbolt: campo ---
confere_valor "passbolt: campo padrão é password" "passbolt:recurso-teste" "$SECRET"
confere_valor "passbolt: #password explícito" "passbolt:recurso-teste#password" "$SECRET"
confere_valor "passbolt: #description" "passbolt:recurso-teste#description" "$DESC"
confere_valor "passbolt: #username" "passbolt:recurso-teste#username" "$USUARIO"
confere_valor "passbolt: #uri" "passbolt:recurso-teste#uri" "$URI_S"

# --- passbolt://: sinônimo de passbolt: ---
confere_despacho "passbolt:// resolve por UUID" "passbolt://11111111-2222-3333-4444-555555555555" "get resource --id 11111111-2222-3333-4444-555555555555"
confere_valor "passbolt:// campo padrão é password" "passbolt://recurso-teste" "$SECRET"
confere_valor "passbolt:// #description" "passbolt://recurso-teste#description" "$DESC"

# passbolt:// e passbolt: dão a mesma saída e o mesmo exit code com o mesmo stub
for campo in "" "#description" "#senha"; do
  run "$STUBS" "passbolt:recurso-teste$campo"; rc_a=$?; cp "$TMP/out" "$TMP/out-a"
  run "$STUBS" "passbolt://recurso-teste$campo"; rc_b=$?
  if [ "$rc_a" -eq "$rc_b" ] && cmp -s "$TMP/out-a" "$TMP/out"; then
    ok "passbolt:// igual a passbolt: ($campo)"
  else
    falha "passbolt:// igual a passbolt: ($campo)" "exit $rc_a x $rc_b"
  fi
done

# passbolt:// vazio: exit 2 antes de chamar qualquer CLI
run "$STUBS" "passbolt://"; rc=$?
if [ "$rc" -eq 2 ] && [ ! -s "$ARGV_LOG" ]; then
  ok "passbolt:// vazio exit 2, CLI não chamado"
else
  falha "passbolt:// vazio exit 2, CLI não chamado" "exit $rc"
fi

# campo fora da lista (ou vazio): exit 2 antes de chamar qualquer CLI
for ref in "passbolt:recurso-teste#senha" "passbolt:recurso-teste#" "passbolt:recurso-teste#Password"; do
  run "$STUBS" "$ref"; rc=$?
  if [ "$rc" -eq 2 ] && [ ! -s "$ARGV_LOG" ]; then
    ok "campo inválido exit 2, CLI não chamado ($ref)"
  else
    falha "campo inválido exit 2, CLI não chamado ($ref)" "exit $rc"
  fi
done

# campo presente mas vazio no recurso: falha, sem stdout
STUB_DESC="" run "$STUBS" "passbolt:recurso-teste#description"; rc=$?
if [ "$rc" -eq 1 ] && [ ! -s "$TMP/out" ]; then
  ok "campo vazio resulta em falha (passbolt #description)"
else
  falha "campo vazio resulta em falha (passbolt #description)" "exit $rc"
fi

# --- referência iniciada em '-': exit 2 com 'referência inválida', CLI não chamado ---
for ref in "pass:-x" "gopass:-x" "passbolt:-recurso-teste" "passbolt://-x" "passbolt://-recurso-teste" "vault:-kv/x#k" "vault:kv/-x#k" "vault:kv/x#-k"; do
  run "$STUBS" "$ref"; rc=$?
  if [ "$rc" -eq 2 ] && grep -q "referência inválida" "$TMP/err" && [ ! -s "$TMP/out" ] && [ ! -s "$ARGV_LOG" ]; then
    ok "referência iniciada em '-' rejeitada, CLI não chamado ($ref)"
  else
    falha "referência iniciada em '-' rejeitada, CLI não chamado ($ref)" "exit $rc"
  fi
done

# --- pass: só a 1ª linha ---
if run "$STUBS" "pass:a/b" && ! grep -q "linha-extra" "$TMP/out"; then ok "pass: devolve só a 1ª linha"; else falha "pass: devolve só a 1ª linha"; fi

# --- sem newline final ---
for ref in "op://c/i/f" "pass:x" "gopass:x" "passbolt:recurso-teste" "vault:kv/x#k"; do
  if run "$STUBS" "$ref" && [ "$(wc -c < "$TMP/out")" -eq "${#SECRET}" ]; then
    ok "sem newline final ($ref)"
  else
    falha "sem newline final ($ref)" "$(wc -c < "$TMP/out") bytes, esperado ${#SECRET}"
  fi
done

# --- valor vazio falha ---
for ref in "op://c/i/f" "pass:x" "gopass:x" "passbolt:recurso-teste" "vault:kv/x#k"; do
  if STUB_VALUE="" run "$STUBS" "$ref"; then
    falha "valor vazio falha ($ref)" "exit 0"
  elif [ ! -s "$TMP/out" ]; then
    ok "valor vazio falha ($ref)"
  else
    falha "valor vazio falha ($ref)" "stdout não vazio"
  fi
done

# --- mensagens sem dois-pontos duplicado (esquema:: ) ---
for ref in "pass:x" "gopass:x"; do
  STUB_VALUE="" run "$STUBS" "$ref"
  if grep -q '::' "$TMP/err"; then
    falha "sem '::' na mensagem de valor vazio ($ref)" "$(cat "$TMP/err")"
  else
    ok "sem '::' na mensagem de valor vazio ($ref)"
  fi
done
for caso in "pass:x|pass" "gopass:x|gopass" "passbolt:recurso-teste|passbolt" "vault:kv/x#k|vault"; do
  IFS='|' read -r ref ausente <<<"$caso"
  run "$(path_sem "$ausente")" "$ref"
  if grep -q '::' "$TMP/err"; then
    falha "sem '::' na mensagem de CLI ausente ($ref)" "$(cat "$TMP/err")"
  else
    ok "sem '::' na mensagem de CLI ausente ($ref)"
  fi
done

# --- esquema desconhecido / ausente: exit 2 ---
for ref in "foo:bar" "semesquema" "vault:semchave" "vault:kv/x#"; do
  run "$STUBS" "$ref"; rc=$?
  if [ "$rc" -eq 2 ]; then ok "exit 2 para '$ref'"; else falha "exit 2 para '$ref'" "exit $rc"; fi
done
run "$STUBS"; rc=$?
if [ "$rc" -eq 2 ] && grep -q "Uso" "$TMP/err"; then ok "exit 2 sem argumento, com uso"; else falha "exit 2 sem argumento, com uso" "exit $rc"; fi

# --- CLI ausente: exit 3 apontando o runbook ---
casos=(
  "op://c/i/f|op op-sa|1password"
  "pass:x|pass|pass-gopass"
  "gopass:x|gopass|pass-gopass"
  "passbolt:recurso-teste|passbolt|passbolt"
  "vault:kv/x#k|vault|vault"
)
for caso in "${casos[@]}"; do
  IFS='|' read -r ref ausentes prov <<<"$caso"
  # shellcheck disable=SC2086
  run "$(path_sem $ausentes)" "$ref"; rc=$?
  if [ "$rc" -eq 3 ] && grep -qF "providers/$prov/runbook-linux.md" "$TMP/err"; then
    ok "exit 3 com runbook ($ref)"
  else
    falha "exit 3 com runbook ($ref)" "exit $rc"
  fi
done

# --- o segredo nunca aparece em argv nem em stderr ---
for ref in "op://c/i/f" "pass:x" "gopass:x" "passbolt:recurso-teste" "vault:kv/x#k"; do
  run "$STUBS" "$ref"
  if grep -qF -- "$SECRET" "$ARGV_LOG" || grep -qF -- "$SECRET" "$TMP/err"; then
    falha "segredo fora de argv/stderr ($ref)"
  else
    ok "segredo fora de argv/stderr ($ref)"
  fi
done

# --- falha do provider não vaza valor nem caminho no stderr ---
make_stub pass 'printf "%s\n" "$STUB_VALUE" >&2; exit 1'
run "$STUBS" "pass:caminho/sigiloso"; rc=$?
if [ "$rc" -ne 0 ] && ! grep -qF -- "$SECRET" "$TMP/err" && ! grep -qF "caminho/sigiloso" "$TMP/err"; then
  ok "erro do provider sem valor nem caminho"
else
  falha "erro do provider sem valor nem caminho" "exit $rc"
fi

# --- A1/A3: op-sa x op conforme o arquivo de token ---
TOKFILE="$TMP/inexistente" run "$STUBS" "op://cofre/item/campo"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF "/op read" "$ARGV_LOG" && ! grep -qF "/op-sa" "$ARGV_LOG"; then ok "A3: sem token file usa op"; else falha "A3: sem token file usa op" "exit $rc"; fi
run "$STUBS" "op://cofre/item/campo"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF "/op-sa read" "$ARGV_LOG"; then ok "A3: com token file usa op-sa"; else falha "A3: com token file usa op-sa" "exit $rc"; fi
: > "$TMP/tok-vazio"; printf '\r\n' > "$TMP/tok-crlf"
for tf in "$TMP/tok-vazio" "$TMP/tok-crlf"; do
  TOKFILE="$tf" run "$STUBS" "op://cofre/item/campo"; rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$ARGV_LOG" ] && [ ! -s "$TMP/out" ] && grep -q "vazio" "$TMP/err"; then
    ok "A3: token file vazio falha sem chamar op ($(basename "$tf"))"
  else
    falha "A3: token file vazio falha sem chamar op ($(basename "$tf"))" "exit $rc"
  fi
done
# A1: op-sa real (script do repo) com token vazio: exit 1, op stub não chamado
OPSA_DIR="$TMP/opsa-real"; mkdir -p "$OPSA_DIR"
ln -sf "$HERE/../scripts/op-sa" "$OPSA_DIR/op-sa"
for f in "$STUBS"/*; do [ "$(basename "$f")" = op-sa ] || ln -sf "$f" "$OPSA_DIR/$(basename "$f")"; done
for tf in "$TMP/tok-vazio" "$TMP/tok-crlf"; do
  : > "$ARGV_LOG"
  env PATH="$OPSA_DIR" OP_SA_TOKEN_FILE="$tf" ARGV_LOG="$ARGV_LOG" STUB_VALUE="$SECRET" "$BASH_BIN" "$OPSA_DIR/op-sa" read op://c/i/f > "$TMP/out" 2> "$TMP/err"; rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$ARGV_LOG" ] && [ ! -s "$TMP/out" ] && grep -q "token vazio" "$TMP/err"; then
    ok "A1: op-sa com token vazio exit 1, op não chamado ($(basename "$tf"))"
  else
    falha "A1: op-sa com token vazio exit 1, op não chamado ($(basename "$tf"))" "exit $rc"
  fi
done
# op:// de item inteiro: exit 2, CLI não chamado
for ref in "op://cofre/item" "op://cofre" "op://cofre//campo"; do
  run "$STUBS" "$ref"; rc=$?
  if [ "$rc" -eq 2 ] && [ ! -s "$ARGV_LOG" ]; then ok "op:// incompleto rejeitado ($ref)"; else falha "op:// incompleto rejeitado ($ref)" "exit $rc"; fi
done

# --- A2: pass exige arquivo do store ---
make_stub pass 'printf "%s\nlinha-extra\n" "$STUB_VALUE"'
for ref in "pass:Business" "pass:dir-sigiloso" "pass:ausente-xyz" "pass:a/../Business"; do
  run "$STUBS" "$ref"; rc=$?
  if [ "$rc" -ne 0 ] && [ ! -s "$TMP/out" ] && [ ! -s "$ARGV_LOG" ] && ! grep -qF "${ref#pass:}" "$TMP/err"; then
    ok "A2: pass: rejeita não-arquivo, sem vazar caminho ($ref)"
  else
    falha "A2: pass: rejeita não-arquivo, sem vazar caminho ($ref)" "exit $rc"
  fi
done
confere_valor "A2: pass: arquivo válido passa" "pass:Business/conta" "$SECRET"
# passbolt ambíguo: falha, nunca escolhe o primeiro
AMB='[{"id":"11111111-2222-3333-4444-555555555555","name":"recurso-a"},{"id":"66666666-2222-3333-4444-555555555555","name":"recurso-b"}]'
STUB_LIST="$AMB" run "$STUBS" "passbolt:recurso"; rc=$?
if [ "$rc" -eq 1 ] && [ ! -s "$TMP/out" ] && ! grep -q "get resource" "$ARGV_LOG"; then ok "A2: passbolt ambíguo falha"; else falha "A2: passbolt ambíguo falha" "exit $rc"; fi
# vault: valor estruturado (mapa/lista) não é segredo escalar
for estr in '{"a":"b"}' '["x","y"]'; do
  STUB_VALUE="$estr" run "$STUBS" "vault:kv/x#k"; rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$TMP/out" ]; then ok "A2: vault: saída estruturada falha ($estr)"; else falha "A2: vault: saída estruturada falha ($estr)" "exit $rc"; fi
done
# vault: sem chave já é exit 2 (ver acima); aqui, escalar JSON continua valendo
STUB_VALUE="12345" run "$STUBS" "vault:kv/x#k"; rc=$?
if [ "$rc" -eq 0 ]; then ok "vault: escalar numérico passa"; else falha "vault: escalar numérico passa" "exit $rc"; fi


# --- R1: estado do token independe de onde está o op-sa ---
# op "sentinela": registra só a presença de OP_SERVICE_ACCOUNT_TOKEN, nunca o valor
R1="$TMP/r1"; mkdir -p "$R1/bin" "$R1/inst" "$R1/path"
for u in jq readlink dirname tr head env bash; do ln -sf "$(command -v "$u")" "$R1/path/$u"; done
printf '#!%s\nif [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then t=presente; else t=ausente; fi\nprintf "op token=%%s\\n" "$t" >> "$ARGV_LOG"\nprintf "%%s\\n" "$STUB_VALUE"\n' "$BASH_BIN" > "$R1/path/op"
chmod +x "$R1/path/op"
# cópia do repo com op-sa irmão do vault-read; instalação por symlink fora do PATH do teste
mkdir -p "$R1/repo"; cp "$HERE/../scripts/vault-read.sh" "$HERE/../scripts/op-sa" "$HERE/../scripts/lib.sh" "$R1/repo/"
ln -sf "$R1/repo/vault-read.sh" "$R1/inst/vault-read"
mkdir -p "$TMP/tok-dir"
run_r1() { # run_r1 <script> <token file> ; PATH sem op-sa
  : > "$ARGV_LOG"
  env PATH="$R1/path" OP_SA_TOKEN_FILE="$2" ARGV_LOG="$ARGV_LOG" STUB_VALUE="$SECRET" "$BASH_BIN" "$1" op://c/i/f > "$TMP/out" 2> "$TMP/err"
}
for tf in "$TMP/tok-vazio" "$TMP/tok-crlf" "$TMP/tok-dir"; do
  run_r1 "$R1/repo/vault-read.sh" "$tf"; rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$ARGV_LOG" ] && [ ! -s "$TMP/out" ]; then
    ok "R1: sem op-sa no PATH, token $(basename "$tf") falha sem chamar op"
  else
    falha "R1: sem op-sa no PATH, token $(basename "$tf") falha sem chamar op" "exit $rc"
  fi
done
run_r1 "$R1/repo/vault-read.sh" "$TOKFILE_OK"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF "token=presente" "$ARGV_LOG" && [ "$(cat "$TMP/out")" = "$SECRET" ]; then ok "R1: sem op-sa no PATH, token ok usa o op-sa irmão"; else falha "R1: sem op-sa no PATH, token ok usa o op-sa irmão" "exit $rc"; fi
run_r1 "$R1/inst/vault-read" "$TOKFILE_OK"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF "token=presente" "$ARGV_LOG"; then ok "R1: invocação por symlink resolve o op-sa irmão"; else falha "R1: invocação por symlink resolve o op-sa irmão" "exit $rc"; fi
run_r1 "$R1/repo/vault-read.sh" "$TMP/inexistente"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF "token=ausente" "$ARGV_LOG"; then ok "R1: sem op-sa e sem token usa op direto"; else falha "R1: sem op-sa e sem token usa op direto" "exit $rc"; fi

# --- R2: lista inválida do passbolt falha antes de get resource ---
for lista in '<html>oops' '{"x":1}' 'null'; do
  STUB_LIST="$lista" run "$STUBS" "passbolt:recurso-teste"; rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$TMP/out" ] && ! grep -q "get resource" "$ARGV_LOG" && ! grep -qF "oops" "$TMP/err"; then
    ok "R2: lista inválida falha sem chamar get resource ($lista)"
  else
    falha "R2: lista inválida falha sem chamar get resource ($lista)" "exit $rc"
  fi
done
echo
echo "Resumo: $PASS OK, $FAIL FALHA"
[ "$FAIL" -eq 0 ]
