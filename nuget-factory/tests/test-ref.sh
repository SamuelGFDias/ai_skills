#!/usr/bin/env bash
# Testa a resolucao da senha do Nexus em lib.sh (NEXUS_PASSWORD_REF, legado, ausencia),
# o escape da config do curl e que os scripts nexus-* nao expoem a senha no argv.
# Usa vault-read e curl falsos no PATH; nenhum cofre nem servidor real e tocado.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$DIR/../scripts/lib.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir "$TMP/bin"
cat > "$TMP/bin/vault-read" <<'FAKE'
#!/usr/bin/env bash
printf '%s' "$1" > "$FAKE_LOG"
case "$1" in
  falha:*) exit 1 ;;
  *) printf '%s' "${FAKE_SECRET:-segredo-de-teste}" ;;
esac
FAKE
chmod +x "$TMP/bin/vault-read"

# curl falso: grava o proprio argv e o stdin (onde vai a config -K -) e responde o que os scripts esperam.
cat > "$TMP/bin/curl" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_ARGV"
cat > "$FAKE_STDIN"
case "$*" in
  *"/repositories"*) printf '[]' ;;
  *"/search"*) printf '{"items":[]}' ;;
  *) printf '204' ;;
esac
FAKE
chmod +x "$TMP/bin/curl"

FALHAS=0
ok() { echo "OK:   $1"; }
ko() { echo "FALHA: $1"; FALHAS=$((FALHAS + 1)); }

# roda <env...> -- imprime stdout em $TMP/out e stderr em $TMP/err; status em $RC
# NEXUS_USER e removido do ambiente herdado; cada caso passa o seu quando precisa.
roda() {
  env -u NEXUS_PASSWORD_REF -u NEXUS_PASSBOLT_RESOURCE_ID -u NEXUS_USER HOME="$TMP/home" \
    PATH="$TMP/bin:$PATH" FAKE_LOG="$TMP/log" "$@" \
    bash -c 'source "$0"; nexus_exec "printf %s \"\$NEXUS_PASSWORD\""' "$LIB" \
    > "$TMP/out" 2> "$TMP/err"
  RC=$?
}

# 1) NEXUS_PASSWORD_REF
roda NEXUS_USER=usuario-teste NEXUS_PASSWORD_REF="op://cofre/item/campo"
[[ $RC -eq 0 && "$(<"$TMP/out")" == "segredo-de-teste" ]] && ok "REF resolve a senha" || ko "REF resolve a senha (rc=$RC)"
[[ "$(<"$TMP/log")" == "op://cofre/item/campo" ]] && ok "vault-read recebeu a referencia" || ko "vault-read recebeu a referencia"
[[ ! -s "$TMP/err" ]] && ok "REF sem aviso" || ko "REF sem aviso"

# 2) legado com aviso (sem vazar o ID)
ID="id-fake-0001"
roda NEXUS_USER=usuario-teste NEXUS_PASSBOLT_RESOURCE_ID="$ID"
[[ $RC -eq 0 && "$(<"$TMP/out")" == "segredo-de-teste" ]] && ok "legado resolve a senha" || ko "legado resolve a senha (rc=$RC)"
[[ "$(<"$TMP/log")" == "passbolt://$ID" ]] && ok "legado vira passbolt://<id>" || ko "legado vira passbolt://<id>"
grep -q "depreciada" "$TMP/err" && ok "aviso de depreciacao" || ko "aviso de depreciacao"
! grep -q "$ID" "$TMP/err" && ok "aviso sem o ID" || ko "aviso sem o ID"

# 3) REF tem prioridade sobre o legado
roda NEXUS_USER=usuario-teste NEXUS_PASSWORD_REF="pass:x" NEXUS_PASSBOLT_RESOURCE_ID="$ID"
[[ "$(<"$TMP/log")" == "pass:x" && ! -s "$TMP/err" ]] && ok "REF vence o legado" || ko "REF vence o legado"

# 4) ausencia de ambos
roda NEXUS_USER=usuario-teste
[[ $RC -ne 0 && ! -s "$TMP/out" ]] && ok "ausencia falha sem valor" || ko "ausencia falha sem valor (rc=$RC)"
grep -q "NEXUS_PASSWORD_REF" "$TMP/err" && ok "mensagem util" || ko "mensagem util"

# 5) vault-read falha
roda NEXUS_USER=usuario-teste NEXUS_PASSWORD_REF="falha:x"
[[ $RC -ne 0 && ! -s "$TMP/out" ]] && ok "falha do vault-read propaga" || ko "falha do vault-read propaga (rc=$RC)"

# 6) NEXUS_USER ausente: falha com mensagem util e nem chega a ler o cofre
rm -f "$TMP/log"
roda NEXUS_PASSWORD_REF="op://cofre/item/campo"
[[ $RC -ne 0 && ! -s "$TMP/out" && ! -e "$TMP/log" ]] && grep -q "NEXUS_USER" "$TMP/err" && ok "ausencia de NEXUS_USER falha antes do cofre, com mensagem util" || ko "ausencia de NEXUS_USER falha antes do cofre (rc=$RC)"

# roda_script <script> [args...]: roda scripts/<script> com curl e vault-read falsos no PATH.
# stdin recebe "y" para a confirmacao do delete; argv e stdin do curl vao para $TMP/argv e $TMP/stdin.
roda_script() {
  local script="$1"; shift
  rm -f "$TMP/argv" "$TMP/stdin" "$TMP/log"
  printf 'y\n' | env -u NEXUS_PASSBOLT_RESOURCE_ID HOME="$TMP/home" \
    PATH="$TMP/bin:$PATH" FAKE_LOG="$TMP/log" FAKE_ARGV="$TMP/argv" FAKE_STDIN="$TMP/stdin" \
    NEXUS_USER=usuario-teste NEXUS_PASSWORD_REF="op://cofre/item/campo" \
    bash "$DIR/../scripts/$script" "$@" > "$TMP/out" 2> "$TMP/err"
  RC=$?
}

# 7) nexus-configure-project.sh sem NEXUS_USER: falha antes de gerar o NuGet.Config
mkdir "$TMP/projeto"
env -u NEXUS_USER HOME="$TMP/home" PATH="$TMP/bin:$PATH" \
  bash "$DIR/../scripts/nexus-configure-project.sh" "$TMP/projeto" > "$TMP/out" 2> "$TMP/err"
RC=$?
[[ $RC -ne 0 && ! -e "$TMP/projeto/NuGet.Config" ]] && ok "configure sem NEXUS_USER falha sem criar NuGet.Config" || ko "configure sem NEXUS_USER falha sem criar NuGet.Config (rc=$RC)"
grep -q "NEXUS_USER" "$TMP/err" && ok "configure: mensagem cita NEXUS_USER" || ko "configure: mensagem cita NEXUS_USER"

# 8) nos 3 scripts com curl: senha fora do argv do curl (sem -u) e presente no stdin (-K -)
chk_segredo() {
  local rotulo="$1"
  [[ $RC -eq 0 ]] && ok "$rotulo: rc 0" || ko "$rotulo: rc=$RC ($(<"$TMP/err"))"
  [[ -s "$TMP/argv" ]] && ! grep -q "segredo-de-teste" "$TMP/argv" && ok "$rotulo: segredo fora do argv do curl" || ko "$rotulo: segredo fora do argv do curl"
  [[ -s "$TMP/argv" ]] && ! grep -qxF -- "-u" "$TMP/argv" && ok "$rotulo: sem flag -u" || ko "$rotulo: sem flag -u"
  grep -qxF 'user = "usuario-teste:segredo-de-teste"' "$TMP/stdin" && ok "$rotulo: segredo chega ao stdin (-K -)" || ko "$rotulo: segredo chega ao stdin (-K -)"
}
roda_script nexus-search.sh pacote-teste
chk_segredo "search"
roda_script nexus-list-repos.sh
chk_segredo "list-repos"
roda_script nexus-delete-component.sh 42
chk_segredo "delete-component"

# 9) escape de " e \ na linha de config: user = "us\"r:a\\b\"c"
NEXUS_USER='us"r' NEXUS_PASSWORD='a\b"c' bash -c 'source "$0"; curl_user_cfg' "$LIB" > "$TMP/out" 2> "$TMP/err"
RC=$?
[[ $RC -eq 0 && "$(<"$TMP/out")" == 'user = "us\"r:a\\b\"c"' ]] && ok "escape de \" e \\ na config do curl" || ko "escape de \" e \\ na config do curl (saida: $(<"$TMP/out"))"

# 10) entrada maliciosa: o valor nao vira comando, chega ao curl como dado e o segredo segue fora do argv
PWNED="/tmp/PWNED-$$"
MAL_APOSTROFO="x'; touch $PWNED #"
MAL_SUBSTITUICAO="\$(touch $PWNED)"
MAL_ESPACO_ASPAS='nome com "aspas" e espaco'

# chk_entrada <rotulo> <linha-esperada-no-argv>: sem PWNED, valor como dado no argv, segredo fora do argv
chk_entrada() {
  local rotulo="$1" esperada="$2"
  [[ $RC -eq 0 ]] && ok "$rotulo: rc 0" || ko "$rotulo: rc=$RC ($(<"$TMP/err"))"
  [[ ! -e "$PWNED" ]] && ok "$rotulo: nenhum comando executado" || ko "$rotulo: PWNED foi criado"
  [[ -s "$TMP/argv" ]] && grep -qxF -- "$esperada" "$TMP/argv" && ok "$rotulo: valor chega ao curl como dado" || ko "$rotulo: valor chega ao curl como dado"
  [[ -s "$TMP/argv" ]] && ! grep -q "segredo-de-teste" "$TMP/argv" && ok "$rotulo: segredo fora do argv" || ko "$rotulo: segredo fora do argv"
  grep -qxF 'user = "usuario-teste:segredo-de-teste"' "$TMP/stdin" && ok "$rotulo: segredo no stdin (-K -)" || ko "$rotulo: segredo no stdin (-K -)"
}

for valor in "$MAL_APOSTROFO" "$MAL_SUBSTITUICAO" "$MAL_ESPACO_ASPAS"; do
  rm -f "$PWNED"
  roda_script nexus-search.sh "$valor"
  chk_entrada "search [$valor]" "name=$valor"
  rm -f "$PWNED"
  roda_script nexus-delete-component.sh "$valor"
  chk_entrada "delete [$valor]" "https://nexus.saude.rj.gov.br/service/rest/v1/components/$valor"
done

# list-repos nao recebe argumento: a entrada maliciosa entra por NEXUS_USER (valor de ambiente)
for valor in "$MAL_APOSTROFO" "$MAL_SUBSTITUICAO"; do
  rm -f "$PWNED" "$TMP/argv" "$TMP/stdin" "$TMP/log"
  env -u NEXUS_PASSBOLT_RESOURCE_ID HOME="$TMP/home" PATH="$TMP/bin:$PATH" FAKE_LOG="$TMP/log" \
    FAKE_ARGV="$TMP/argv" FAKE_STDIN="$TMP/stdin" NEXUS_USER="$valor" NEXUS_PASSWORD_REF="op://cofre/item/campo" \
    bash "$DIR/../scripts/nexus-list-repos.sh" > "$TMP/out" 2> "$TMP/err"
  RC=$?
  [[ $RC -eq 0 ]] && ok "list-repos [$valor]: rc 0" || ko "list-repos [$valor]: rc=$RC"
  [[ ! -e "$PWNED" ]] && ok "list-repos [$valor]: nenhum comando executado" || ko "list-repos [$valor]: PWNED foi criado"
  grep -qF -- "$valor:segredo-de-teste" "$TMP/stdin" && ok "list-repos [$valor]: usuario chega ao stdin como dado" || ko "list-repos [$valor]: usuario chega ao stdin como dado"
  [[ -s "$TMP/argv" ]] && ! grep -q "segredo-de-teste" "$TMP/argv" && ok "list-repos [$valor]: segredo fora do argv" || ko "list-repos [$valor]: segredo fora do argv"
done
rm -f "$PWNED"

# 11) senha com \n ou \r: curl_user_cfg recusa sem ecoar o valor
for quebra in $'\n' $'\r'; do
  NEXUS_USER=usuario-teste NEXUS_PASSWORD="segredo${quebra}resto" bash -c 'source "$0"; curl_user_cfg' "$LIB" > "$TMP/out" 2> "$TMP/err"
  RC=$?
  rotulo="senha com ${quebra@Q}"
  [[ $RC -ne 0 && ! -s "$TMP/out" ]] && ok "curl_user_cfg recusa $rotulo" || ko "curl_user_cfg recusa $rotulo (rc=$RC)"
  ! grep -q "segredo" "$TMP/err" && ok "curl_user_cfg nao ecoa a senha ($rotulo)" || ko "curl_user_cfg ecoa a senha ($rotulo)"
done

# 12) senha com \n: nexus-search e nexus-delete-component falham antes do curl (stub nao chamado)
roda_quebra() {
  local script="$1"; shift
  rm -f "$TMP/argv" "$TMP/stdin" "$TMP/log"
  printf 'y\n' | env -u NEXUS_PASSBOLT_RESOURCE_ID HOME="$TMP/home" \
    PATH="$TMP/bin:$PATH" FAKE_LOG="$TMP/log" FAKE_ARGV="$TMP/argv" FAKE_STDIN="$TMP/stdin" \
    FAKE_SECRET=$'segredo\nresto' NEXUS_USER=usuario-teste NEXUS_PASSWORD_REF="op://cofre/item/campo" \
    bash "$DIR/../scripts/$script" "$@" > "$TMP/out" 2> "$TMP/err"
  RC=$?
}
roda_quebra nexus-search.sh pacote-teste
[[ $RC -ne 0 && ! -e "$TMP/argv" ]] && ok "search com senha de quebra de linha falha sem chamar o curl" || ko "search com senha de quebra de linha falha sem chamar o curl (rc=$RC)"
! grep -q "resto" "$TMP/err" && ok "search: erro nao ecoa a senha" || ko "search: erro ecoa a senha"
roda_quebra nexus-delete-component.sh 42
[[ $RC -ne 0 && ! -e "$TMP/argv" ]] && ok "delete com senha de quebra de linha falha sem chamar o curl" || ko "delete com senha de quebra de linha falha sem chamar o curl (rc=$RC)"

# 13) NEXUS_USER com & < > " ': NuGet.Config bem formado e com o valor escapado (hosted tem 2 atributos)
USUARIO_XML='a&b<c>d"e'\''f'
PROJ_XML="$TMP/projeto-xml"
mkdir "$PROJ_XML"
env -u NEXUS_PASSBOLT_RESOURCE_ID HOME="$TMP/home" PATH="$TMP/bin:$PATH" NEXUS_USER="$USUARIO_XML" \
  bash "$DIR/../scripts/nexus-configure-project.sh" "$PROJ_XML" --hosted > "$TMP/out" 2> "$TMP/err"
RC=$?
[[ $RC -eq 0 && -s "$PROJ_XML/NuGet.Config" ]] && ok "configure com usuario especial gera NuGet.Config" || ko "configure com usuario especial gera NuGet.Config (rc=$RC, $(<"$TMP/err"))"
python3 -c "import xml.dom.minidom,sys; xml.dom.minidom.parse(sys.argv[1])" "$PROJ_XML/NuGet.Config" 2>/dev/null && ok "NuGet.Config bem formado (XML)" || ko "NuGet.Config bem formado (XML)"
python3 -c "import xml.dom.minidom,sys; d=xml.dom.minidom.parse(sys.argv[1]); v=[e.getAttribute('value') for e in d.getElementsByTagName('add') if e.getAttribute('key')=='Username']; sys.exit(0 if v==[sys.argv[2]]*2 else 1)" "$PROJ_XML/NuGet.Config" "$USUARIO_XML" && ok "Username lido de volta igual ao original" || ko "Username lido de volta igual ao original"

# 14) NEXUS_USER com \n: configure falha antes de criar NuGet.Config
PROJ_NL="$TMP/projeto-nl"
mkdir "$PROJ_NL"
env -u NEXUS_PASSBOLT_RESOURCE_ID HOME="$TMP/home" PATH="$TMP/bin:$PATH" NEXUS_USER=$'us\nr' \
  bash "$DIR/../scripts/nexus-configure-project.sh" "$PROJ_NL" > "$TMP/out" 2> "$TMP/err"
RC=$?
[[ $RC -ne 0 && ! -e "$PROJ_NL/NuGet.Config" ]] && ok "configure com NEXUS_USER de quebra de linha falha sem criar NuGet.Config" || ko "configure com NEXUS_USER de quebra de linha falha sem criar NuGet.Config (rc=$RC)"
grep -q "quebra de linha" "$TMP/err" && ok "configure: mensagem de quebra de linha" || ko "configure: mensagem de quebra de linha"

echo
[[ $FALHAS -eq 0 ]] && echo "Todos os testes passaram." || { echo "$FALHAS falha(s)."; exit 1; }
