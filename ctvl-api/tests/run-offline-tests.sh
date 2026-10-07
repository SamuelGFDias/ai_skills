#!/usr/bin/env bash
# Testes OFFLINE da skill ctvl-api. Nada toca o vault real: usa fixtures e um servidor FALSO em loopback.
# Segredos de teste são gerados em memória a cada execução (nenhum literal neste arquivo).
# Uso: tests/run-offline-tests.sh
set -uo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$TESTS_DIR")"
CTVL="$SKILL_DIR/scripts/ctvl.sh"
CORE="$SKILL_DIR/scripts/ctvl_core.py"
WORK="$(mktemp -d)"
FAKE_PIDS=()
cleanup() {
  for p in "${FAKE_PIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done
  rm -rf "$WORK"
}
trap cleanup EXIT

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/        /' | head -15; }
# expect_rc <rc_esperado> <descrição> <comando...>   (saída em $OUT)
expect_rc() {
  local want="$1" desc="$2"; shift 2
  OUT="$("$@" 2>&1)"; local rc=$?
  if [ "$rc" -eq "$want" ]; then ok "$desc"; else bad "$desc (rc=$rc, esperado $want)" "$OUT"; fi
}
has() { # <padrão> <descrição>   procura em $OUT
  if printf '%s' "$OUT" | grep -Eq -- "$1"; then ok "$2"; else bad "$2 (padrão ausente: $1)" "$OUT"; fi
}
hasnt() {
  if printf '%s' "$OUT" | grep -Eq -- "$1"; then bad "$2 (padrão presente: $1)" "$OUT"; else ok "$2"; fi
}
rnd() { python3 -c 'import secrets;print(secrets.token_hex(12))'; }

echo "== 1. sintaxe"
for f in "$SKILL_DIR"/scripts/*.sh; do
  if bash -n "$f"; then ok "bash -n $(basename "$f")"; else bad "bash -n $(basename "$f")"; fi
done
if python3 -m py_compile "$CORE" "$SKILL_DIR"/scripts/ctvlpy/*.py "$TESTS_DIR/fake_ctvl_server.py" 2>"$WORK/pyc.err"; then ok "py_compile"; else bad "py_compile" "$(cat "$WORK/pyc.err")"; fi
find "$SKILL_DIR" -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null
command -v shellcheck >/dev/null && { OUT="$(shellcheck -x -e SC1091 "$SKILL_DIR"/scripts/*.sh 2>&1)" && ok "shellcheck" || bad "shellcheck" "$OUT"; }

echo "== 2. nomes e configuração (offline)"
expect_rc 0 "names: usuário conforme" "$CTVL" names sindras_cns settorj_cns_3_left sindras_svc_tokenize
has "settorj +cns +3_left" "names extrai sistema/datatype/esquema"
expect_rc 1 "names: fora do padrão é reportado (não ignorado)" "$CTVL" names ctvl_cpf_total admin
has "FORA DO PADRÃO.*ctvl" "names aponta o sistema desconhecido"
expect_rc 0 "names: máscara cns_3_left" "$CTVL" names --kind mask cns_3_left settorj_cns_3_left
expect_rc 0 "check-config do exemplo" "$CTVL" check-config --file "$SKILL_DIR/references/exemplo-config.yaml"
has "BLOQUEIO +templates SINDRAS_CPF" "charset pendente vira bloqueio"
expect_rc 0 "plan offline sobre o exemplo (sem rede)" "$CTVL" plan --offline --empty-state --file "$SKILL_DIR/references/exemplo-config.yaml"
has "CRIAR +usuário +settorj_cns_3_left" "plan expande defaults+sistemas"
has "settorj_cns_3_left" "override do settorj gera máscara própria"
hasnt "senha.*=" "plan não mostra senha"
DOCS=/home/samuel.dias/dev/sindras/docs/tokenizacao-ctvl
if [ -d "$DOCS" ]; then
  expect_rc 0 "plan offline sobre docs/tokenizacao-ctvl" "$CTVL" plan --offline --empty-state --docs-dir "$DOCS" --email-domain example.invalid
  has "BLOQUEADO +tokengroup +SINDRAS" "docs: chave do tokengroup não adivinhada"
  has "fora do padrão" "docs: usuários ctvl_* sinalizados"
fi

echo "== 3. export determinístico e sem segredos (fixtures)"
python3 - "$TESTS_DIR/fixtures" "$WORK/shuffled" <<'EOF'
import json, os, random, sys
src, dst = sys.argv[1], sys.argv[2]
os.makedirs(dst)
random.seed(7)
for f in os.listdir(src):
    d = json.load(open(os.path.join(src, f)))
    random.shuffle(d["results"])
    json.dump(d, open(os.path.join(dst, f), "w"))
EOF
python3 -B "$CORE" export --state-dir "$TESTS_DIR/fixtures" --ambiente teste --out "$WORK/e1.yaml" 2>/dev/null
python3 -B "$CORE" export --state-dir "$WORK/shuffled" --ambiente teste --out "$WORK/e2.yaml" 2>/dev/null
if cmp -s "$WORK/e1.yaml" "$WORK/e2.yaml"; then ok "export idêntico com a ordem das respostas embaralhada"; else bad "export não determinístico"; fi
OUT="$(cat "$WORK/e1.yaml")"
hasnt "pbkdf2|fixturehash|eyJ|[Bb]earer" "export sem hash de senha/JWT/Authorization"
hasnt "(^|[^a-z_])password:|secret|session" "export sem campos de senha/segredo/sessão"
hasnt "idkey|idtenant|idmask|\bid:" "export sem ids internos"
hasnt "([0-9]{1,3}\.){3}[0-9]{1,3}" "export sem IPs"
has "fora_do_padrao" "export marca usuários fora da convenção"
has "convencao_nome" "export traz sistema/datatype/esquema dos conformes"
expect_rc 0 "o export é aceito de volta como configuração" "$CTVL" check-config --file "$WORK/e1.yaml"
expect_rc 0 "plan do export contra o mesmo estado: nada a criar" "$CTVL" plan --offline --state-dir "$TESTS_DIR/fixtures" --file "$WORK/e1.yaml"
hasnt "CRIAR|ATUALIZAR|CONFLITO" "round-trip export -> plan é idempotente"
expect_rc 0 "list all (tabelas)" "$CTVL" list --offline all --state-dir "$TESTS_DIR/fixtures"
has "sindras_cns_3_left +sim +cns_3_left" "list mostra máscara do usuário"
expect_rc 0 "list yaml" "$CTVL" list --offline users --format yaml --state-dir "$TESTS_DIR/fixtures"
expect_rc 0 "probe-refs sobre fixtures" "$CTVL" probe-refs --offline --state-dir "$TESTS_DIR/fixtures"
has "template.tenant +- +name" "probe-refs encontra evidência de nome"

echo "== 3b. mudanças sobre estado existente (fixtures, offline)"
sed 's/^    keep_left: 3$/    keep_left: 4/' "$WORK/e1.yaml" >"$WORK/mut-tpl.yaml"
expect_rc 0 "plan: mudar a receita de template existente" "$CTVL" plan --offline --state-dir "$TESTS_DIR/fixtures" --file "$WORK/mut-tpl.yaml"
has "CONFLITO +template" "receita alterada vira CONFLITO (não ATUALIZAR)"
has "keep_left.*3.*4" "diff mostra atual -> novo"
expect_rc 1 "plan --check falha com conflito" "$CTVL" plan --offline --state-dir "$TESTS_DIR/fixtures" --file "$WORK/mut-tpl.yaml" --check
expect_rc 0 "plan com --allow-breaking-update" "$CTVL" plan --offline --state-dir "$TESTS_DIR/fixtures" --file "$WORK/mut-tpl.yaml" --allow-breaking-update
has "ATUALIZAR +template" "com a flag explícita vira ATUALIZAR"
python3 - "$WORK/e1.yaml" "$WORK/mut-misc.yaml" <<'EOF2'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
r = d["recursos"]
for m in r["mascaras"]:
    if m["nome"] == "cns_3_left":
        m["show_left"] = 2
for t in r["tokengroups"]:
    if t["nome"] == "SINDRAS":
        t["chave"] = "SETTORJ_KEY"
for p in r["permissoes_usuarios"]:
    if p["usuario"] == "sindras_cns_3_left":
        p["detokenize"] = False
yaml.safe_dump(d, open(sys.argv[2], "w"), allow_unicode=True, sort_keys=False)
EOF2
expect_rc 0 "plan: máscara, chave de tokengroup e permissão alteradas" "$CTVL" plan --offline --state-dir "$TESTS_DIR/fixtures" --file "$WORK/mut-misc.yaml"
has "ATUALIZAR +máscara +cns_3_left" "máscara alterada vira ATUALIZAR"
has "CONFLITO +tokengroup +SINDRAS" "trocar a chave do tokengroup vira CONFLITO"
has "ATUALIZAR +perm.usuário +sindras_cns_3_left@SINDRAS_KEY" "permissão alterada vira ATUALIZAR"
has "CRIAR|MANUAL|OK" "plano completo renderizado"
expect_rc 0 "plan --show-extra lista o que não está no arquivo (nunca removido)" "$CTVL" plan --offline --state-dir "$TESTS_DIR/fixtures" --file "$SKILL_DIR/references/exemplo-config.yaml" --show-extra
has "NUNCA removidos" "extras não são removidos"
hasnt "REMOVER|DELETAR|DELETE" "plan não tem operação de remoção"

echo "== 4. segurança do cliente e das credenciais"
export CTVL_CREDENTIALS_FILE="$WORK/credentials"
export XDG_CACHE_HOME="$WORK/cache"
printf 'fake.HOST=127.0.0.1:1\n' >"$CTVL_CREDENTIALS_FILE"
chmod 644 "$CTVL_CREDENTIALS_FILE"
expect_rc 1 "recusa arquivo de credenciais com modo != 600" "$CTVL" token fake
has "chmod 600" "mensagem orienta chmod 600"
chmod 600 "$CTVL_CREDENTIALS_FILE"
expect_rc 1 "sem credencial ADMIN: falha clara (não usa credencial de dados)" "$CTVL" token fake
has "NÃO use credencial de tokenize" "mensagem proíbe credencial de dados na API admin"
expect_rc 1 "apelido inválido" "$CTVL" token "../x"
printf 'prd.HOST=127.0.0.1:1\nprd.INSECURE_TLS=1\n' >>"$CTVL_CREDENTIALS_FILE"
expect_rc 1 "TLS inseguro proibido em prd" "$CTVL" token prd
has "proibido no ambiente prd" "mensagem de TLS em prd"
expect_rc 1 "apply sem credencial admin: nem tenta (falha no login)" "$CTVL" apply fake --file "$SKILL_DIR/references/exemplo-config.yaml" --yes
has "credencial ADMIN" "apply cita a credencial admin ausente"
expect_rc 2 "apply --offline não existe (precisa do vault real)" "$CTVL" apply --offline --file "$SKILL_DIR/references/exemplo-config.yaml"

echo "== 5. ponta a ponta contra o servidor FALSO (nome)"
start_fake() { # <ref-mode> <seed.json> -> define FAKE_PORT
  local pf="$WORK/port.$1"
  rm -f "$pf"
  FAKE_ADMIN_USER=fakeadmin FAKE_ADMIN_PASSWORD="$ADMIN_PW" python3 -B "$TESTS_DIR/fake_ctvl_server.py" \
    --ref-mode "$1" --port-file "$pf" --seed "$2" &
  FAKE_PIDS+=("$!")
  for _ in $(seq 1 50); do [ -s "$pf" ] && break; sleep 0.1; done
  FAKE_PORT="$(cat "$pf")"
}
ADMIN_PW="$(rnd)"
PW_SVC="$(rnd)"; PW_PARCIAL="$(rnd)"; PW_TOTAL="$(rnd)"
cat >"$WORK/seed.json" <<EOF
{"users": [
  {"username": "sindras_svc_tokenize", "password": "$PW_SVC"},
  {"username": "sindras_cpf_3_left_2_right", "password": "$PW_PARCIAL", "mask": "cpf_3_left_2_right"}]}
EOF
start_fake name "$WORK/seed.json"
# máscara pré-existente no fake (a mesma que a configuração declara e que o usuário semeado já tem atribuída)
cat >"$WORK/cfg.yaml" <<'EOF'
versao: 1
convencao: {sistemas: [sindras, settorj], datatypes: [cpf, cns]}
api:
  refs: {tokengroup.key: name, template.tenant: name, template.format: name, template.charset: name, user.groups: name, perm_user.key: name}
usuarios_padrao: {email_dominio: example.invalid}
recursos:
  chaves: [{nome: SINDRAS_KEY}]
  grupos: [{nome: app_sindras}]
defaults:
  datatypes:
    cpf:
      template: {format: FPE, charset: Numeric, keep_left: 3, keep_right: 2}
      mascaras: {3_left_2_right: {show_left: 3, show_right: 2, mask_char: "*"}}
      usuarios:
        - {esquema: total, permissoes: [detokenize]}
        - {esquema: 3_left_2_right, permissoes: [detokenize], grupos: [app_sindras]}
  servico:
    - {esquema: tokenize, permissoes: [tokenize]}
sistemas:
  sindras: {tokengroup: SINDRAS, chave: SINDRAS_KEY, datatypes: [cpf]}
EOF
printf 'fake.HOST=127.0.0.1:%s\nfake.SCHEME=http\nfake.ADMIN_USER=fakeadmin\nfake.ADMIN_PASSWORD=%s\n' "$FAKE_PORT" "$ADMIN_PW" >>"$CTVL_CREDENTIALS_FILE"
"$CTVL" admin fake POST /masks/ --body '{"name":"cpf_3_left_2_right","showleft":3,"showright":2,"maskchar":"*"}' --yes >/dev/null 2>&1
expect_rc 0 "envs lista sem expor host/usuário/senha" "$CTVL" envs
hasnt "127\.0\.0\.1|fakeadmin|$ADMIN_PW" "envs não imprime host, usuário nem senha"
expect_rc 0 "token: login e cache" "$CTVL" token fake
hasnt "eyJ|$ADMIN_PW" "token não imprime JWT nem senha"
if [ "$(stat -c %a "$XDG_CACHE_HOME/ctvl-api/fake.jwt")" = "600" ]; then ok "cache do JWT em modo 600"; else bad "cache do JWT sem modo 600"; fi
expect_rc 0 "admin GET --all" "$CTVL" admin fake GET /users/ --all
hasnt "pbkdf2|fakehash" "admin mascara o hash de senha dos usuários"
hasnt "127\.0\.0\.1" "admin mascara o host/IP na saída"
expect_rc 2 "admin POST sem --yes não envia" "$CTVL" admin fake POST /groups/ --body '{"name":"nao_deve_existir"}'
has "NADA foi enviado" "admin avisa que nada foi enviado"
has "vai executar: POST" "admin mostra o que faria antes"
expect_rc 1 "admin recusa --body inline com senha" "$CTVL" admin fake POST /users/ --body '{"username":"x","email":"x@example.invalid","password":"abc"}' --yes
printf '{"name":"grupo_stdin"}' | "$CTVL" admin fake POST /groups/ --body-stdin --yes >/dev/null 2>&1
OUT="$("$CTVL" admin fake GET /groups/ --all 2>&1)"
has "grupo_stdin" "admin --body-stdin"
expect_rc 0 "admin POST com --yes" "$CTVL" admin fake POST /groups/ --body '{"name":"grupo_manual"}' --yes
expect_rc 1 "admin recusa /api-token-auth/" "$CTVL" admin fake POST /api-token-auth/ --body '{"a":1}' --yes
expect_rc 0 "list groups (online)" "$CTVL" list fake groups
has "grupo_manual" "grupo criado aparece na listagem"
expect_rc 0 "plan online" "$CTVL" plan fake --file "$WORK/cfg.yaml"
has "CRIAR +chave +SINDRAS_KEY" "plan: criar chave"
has "OK +usuário +sindras_svc_tokenize" "plan: usuário semeado já existe"
has "OK +máscara|CRIAR +máscara +cpf_3_left_2_right" "plan: máscara avaliada"
expect_rc 2 "apply sem --yes" "$CTVL" apply fake --file "$WORK/cfg.yaml"
has "exige --yes" "apply sem --yes explica"
OUT="$(env -u CTVL_SINDRAS_CPF_TOTAL_PASSWORD "$CTVL" apply fake --file "$WORK/cfg.yaml" --yes 2>&1)"; rc=$?
if [ "$rc" -eq 3 ]; then ok "apply aborta antes de escrever se faltar a senha (env)"; else bad "apply sem senha deveria abortar (rc=$rc)" "$OUT"; fi
has "CTVL_SINDRAS_CPF_TOTAL_PASSWORD" "mensagem cita só o NOME da variável"
grep -v '^api:\|^  refs:' "$WORK/cfg.yaml" >"$WORK/cfg-sem-refs.yaml"
OUT="$(CTVL_SINDRAS_CPF_TOTAL_PASSWORD="$PW_TOTAL" "$CTVL" apply fake --file "$WORK/cfg-sem-refs.yaml" --yes 2>&1)"; rc=$?
if [ "$rc" -eq 3 ]; then ok "sem api.refs e sem evidência (vault vazio): apply se recusa a adivinhar nome x id"; else bad "esperava rc=3 sem api.refs (rc=$rc)" "$OUT"; fi
has "A CONFIRMAR" "mensagem diz que nome x id é a confirmar"
OUT="$(CTVL_SINDRAS_CPF_TOTAL_PASSWORD="$PW_TOTAL" "$CTVL" apply fake --file "$WORK/cfg.yaml" --yes 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "apply --yes"; else bad "apply --yes (rc=$rc)" "$OUT"; fi
has "EXECUTA +POST /tokentemplates/" "apply cria o template"
has "0 ação" "verificação pós-apply: nada pendente"
hasnt "$PW_TOTAL|$ADMIN_PW|eyJ" "apply não imprime senhas nem JWT"
has "password.*\*\*\*" "corpo do usuário é impresso com senha mascarada"
expect_rc 0 "plan após apply" "$CTVL" plan fake --file "$WORK/cfg.yaml"
hasnt "CRIAR|ATUALIZAR|CONFLITO|BLOQUEADO" "idempotência: segundo plan não tem mudanças"
expect_rc 0 "apply repetido" env CTVL_SINDRAS_CPF_TOTAL_PASSWORD="$PW_TOTAL" "$CTVL" apply fake --file "$WORK/cfg.yaml" --yes
has "Nada a aplicar" "apply repetido não faz nada"
"$CTVL" export fake --out "$WORK/live1.yaml" >/dev/null 2>&1
"$CTVL" export fake --out "$WORK/live2.yaml" >/dev/null 2>&1
if cmp -s "$WORK/live1.yaml" "$WORK/live2.yaml"; then ok "export ao vivo é determinístico"; else bad "export ao vivo difere entre execuções"; fi
OUT="$(cat "$WORK/live1.yaml")"
hasnt "pbkdf2|fakehash|eyJ|$ADMIN_PW|$PW_TOTAL" "export ao vivo sem segredos"
curl -s -X POST "http://127.0.0.1:$FAKE_PORT/__test/revoke" >/dev/null
expect_rc 0 "token revogado: renova sozinho e repete" "$CTVL" list fake groups
has "renovando" "avisou da renovação"
# a skill não sabe atribuir máscara: o fake segue o swagger (mask somente leitura)
expect_rc 0 "verify-mask: tokeniza e detokeniza por usuário" env CTVL_SINDRAS_SVC_TOKENIZE_PASSWORD="$PW_SVC" \
  CTVL_SINDRAS_CPF_3_LEFT_2_RIGHT_PASSWORD="$PW_PARCIAL" CTVL_SINDRAS_CPF_TOTAL_PASSWORD="$PW_TOTAL" \
  "$CTVL" verify-mask fake --file "$WORK/cfg.yaml" --sistema sindras --datatype cpf --sample 52998224725
has "sindras_cpf_total +\(sem máscara\) +OK" "usuário sem máscara vê tudo"
has "sindras_cpf_3_left_2_right +cpf_3_left_2_right +OK" "usuário mascarado confere"
sed 's/show_right: 2, mask_char/show_right: 1, mask_char/' "$WORK/cfg.yaml" >"$WORK/cfg-errada.yaml"
expect_rc 1 "verify-mask detecta máscara divergente" env CTVL_SINDRAS_SVC_TOKENIZE_PASSWORD="$PW_SVC" \
  CTVL_SINDRAS_CPF_3_LEFT_2_RIGHT_PASSWORD="$PW_PARCIAL" CTVL_SINDRAS_CPF_TOTAL_PASSWORD="$PW_TOTAL" \
  "$CTVL" verify-mask fake --file "$WORK/cfg-errada.yaml" --sistema sindras --datatype cpf --sample 52998224725
has "DIVERGE" "divergência reportada"

echo "== 6. referências por id: não adivinha na escrita"
printf '{"users": []}' >"$WORK/seed-id.json"
start_fake id "$WORK/seed-id.json"
printf 'fakeid.HOST=127.0.0.1:%s\nfakeid.SCHEME=http\nfakeid.ADMIN_USER=fakeadmin\nfakeid.ADMIN_PASSWORD=%s\n' "$FAKE_PORT" "$ADMIN_PW" >>"$CTVL_CREDENTIALS_FILE"
cat >"$WORK/cfg-id.yaml" <<'EOF'
versao: 1
convencao: {sistemas: [sindras], datatypes: [cpf]}
usuarios_padrao: {email_dominio: example.invalid}
recursos:
  chaves: [{nome: SINDRAS_KEY}]
  grupos: [{nome: app_sindras}]
defaults:
  datatypes:
    cpf:
      template: {format: FPE, charset: Numeric, keep_left: 3, keep_right: 2}
      usuarios:
        - {esquema: total, permissoes: [detokenize], grupos: [app_sindras]}
  servico:
    - {esquema: tokenize, permissoes: [tokenize]}
sistemas:
  sindras: {tokengroup: SINDRAS, chave: SINDRAS_KEY, datatypes: [cpf]}
EOF
export CTVL_SINDRAS_CPF_TOTAL_PASSWORD="$(rnd)" CTVL_SINDRAS_SVC_TOKENIZE_PASSWORD="$(rnd)"
OUT="$("$CTVL" apply fakeid --file "$WORK/cfg-id.yaml" --yes 2>&1)"; rc=$?
if [ "$rc" -eq 3 ]; then ok "apply sem api.refs confirmado falha ANTES de escrever"; else bad "esperava rc=3 (rc=$rc)" "$OUT"; fi
has "A CONFIRMAR" "mensagem diz que o formato é a confirmar"
has "probe-refs" "mensagem indica o probe-refs"
OUT="$("$CTVL" list fakeid groups 2>&1)"
hasnt "app_sindras" "nada foi criado pelo apply abortado"
python3 - "$WORK/cfg-id.yaml" "$WORK/cfg-id-ok.yaml" <<'EOF'
import sys
s = open(sys.argv[1]).read()
s = s.replace("usuarios_padrao:", "api:\n  refs: {tokengroup.key: id, template.tenant: id, template.format: name, template.charset: id, user.groups: id, perm_user.key: id}\nusuarios_padrao:")
open(sys.argv[2], "w").write(s)
EOF
OUT="$("$CTVL" apply fakeid --file "$WORK/cfg-id-ok.yaml" --yes 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "apply com referências por id confirmadas"; else bad "apply por id (rc=$rc)" "$OUT"; fi
expect_rc 0 "plan após apply por id" "$CTVL" plan fakeid --file "$WORK/cfg-id-ok.yaml"
hasnt "CRIAR|ATUALIZAR|CONFLITO|BLOQUEADO" "idempotência com referências por id"
expect_rc 0 "probe-refs ao vivo (id)" "$CTVL" probe-refs fakeid --file "$WORK/cfg-id-ok.yaml"
has "template.tenant +id +id" "probe-refs reconhece id"

echo "== 7. correções da revisão de segurança"
start_fake name "$WORK/seed-id.json"
P7="$FAKE_PORT"
printf 's7.HOST=127.0.0.1:%s\ns7.SCHEME=http\ns7.ADMIN_USER=fakeadmin\ns7.ADMIN_PASSWORD=%s\n' "$P7" "$ADMIN_PW" >>"$CTVL_CREDENTIALS_FILE"
stats() { curl -s "http://127.0.0.1:$1/__test/stats"; }

echo "-- 7.1 permissão e usuário seguem o tokengroup em conflito/bloqueado"
for b in '{"name":"SINDRAS_KEY"}' '{"name":"SETTORJ_KEY"}'; do "$CTVL" admin s7 POST /keys/ --body "$b" --yes >/dev/null 2>&1; done
"$CTVL" admin s7 POST /tokengroups/ --body '{"name":"SINDRAS","key":"SINDRAS_KEY"}' --yes >/dev/null 2>&1
cat >"$WORK/cfg-conf.yaml" <<'EOF'
versao: 1
convencao: {sistemas: [sindras, settorj], datatypes: [cpf]}
api:
  refs: {tokengroup.key: name, template.tenant: name, template.format: name, template.charset: name, user.groups: name, perm_user.key: name}
usuarios_padrao: {email_dominio: example.invalid}
recursos:
  chaves: [{nome: SINDRAS_KEY}, {nome: SETTORJ_KEY}]
  grupos: [{nome: grupo_ok}]
defaults:
  datatypes:
    cpf:
      template: {format: FPE, charset: Numeric, keep_left: 3, keep_right: 2}
      usuarios:
        - {esquema: total, permissoes: [detokenize]}
  servico:
    - {esquema: tokenize, permissoes: [tokenize]}
sistemas:
  sindras: {tokengroup: SINDRAS, chave: SETTORJ_KEY, datatypes: [cpf]}
EOF
expect_rc 0 "plan: sindras declarada com a chave do settorj" "$CTVL" plan s7 --file "$WORK/cfg-conf.yaml"
has "CONFLITO +tokengroup +SINDRAS" "tokengroup com a chave trocada é CONFLITO"
has "BLOQUEADO +perm.usuário +sindras_cpf_total@SETTORJ_KEY.*difere da chave atual 'SINDRAS_KEY'" "permissão sobre a chave de outro sistema é BLOQUEADA"
has "CRIAR +usuário +sindras_cpf_total +PULADO: todas as suas permissões" "usuário criado só para a permissão é pulado junto"
has "CRIAR +usuário +sindras_svc_tokenize +PULADO" "usuário de serviço também"
OUT="$("$CTVL" apply s7 --file "$WORK/cfg-conf.yaml" --yes 2>&1)"; rc=$?
if [ "$rc" -eq 3 ]; then ok "apply sem --skip-blocked aborta antes de escrever"; else bad "apply deveria abortar (rc=$rc)" "$OUT"; fi
OUT="$("$CTVL" apply s7 --file "$WORK/cfg-conf.yaml" --yes --skip-blocked --no-verify 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "apply --yes --skip-blocked aplica só o que é seguro"; else bad "apply --skip-blocked (rc=$rc)" "$OUT"; fi
has "EXECUTA +POST /groups/" "o item independente (grupo) foi aplicado"
has "PULADO +usuário +sindras_cpf_total" "apply pula o usuário"
hasnt "EXECUTA +POST /(users|permissions)" "nenhuma escrita de usuário/permissão saiu"
OUT="$("$CTVL" admin s7 GET /users/ --all 2>&1)"
hasnt "sindras_cpf_total|sindras_svc_tokenize" "o vault não ganhou o usuário do sistema bloqueado"
OUT="$("$CTVL" admin s7 GET /permissions/token/users/ --all 2>&1)"
hasnt "SETTORJ_KEY|sindras" "o vault não ganhou permissão sobre a chave errada"
cat >"$WORK/cfg-dep.yaml" <<'EOF'
versao: 1
convencao: {sistemas: [sindras], datatypes: [cpf]}
usuarios_padrao: {email_dominio: example.invalid}
recursos:
  tokengroups: [{nome: SINDRAS2, chave: NAO_EXISTE_KEY}]
  usuarios: [{nome: sindras_cpf_extra}]
  permissoes_usuarios: [{usuario: sindras_cpf_extra, tokengroup: SINDRAS2, chave: SETTORJ_KEY, detokenize: true}]
EOF
expect_rc 0 "plan: tokengroup bloqueado leva a permissão e o usuário" "$CTVL" plan s7 --file "$WORK/cfg-dep.yaml"
has "BLOQUEADO +tokengroup +SINDRAS2" "tokengroup sem chave existente é BLOQUEADO"
has "BLOQUEADO +perm.usuário +sindras_cpf_extra@SETTORJ_KEY.*difere da chave declarada 'NAO_EXISTE_KEY'" "permissão sobre chave diferente da declarada do tokengroup novo é BLOQUEADA"
has "CRIAR +usuário +sindras_cpf_extra +PULADO" "usuário só de permissão é pulado"

echo "-- 7.2 password_ref só aceita CTVL_<NOME>_PASSWORD e nunca a senha admin"
mkpr() {
  cat >"$WORK/cfg-pr.yaml" <<EOF
versao: 1
convencao: {sistemas: [sindras], datatypes: [cpf]}
usuarios_padrao: {email_dominio: example.invalid}
defaults:
  datatypes:
    cpf:
      template: {format: FPE, charset: Numeric}
      usuarios:
        - {esquema: total, permissoes: [detokenize], password_ref: "$1"}
sistemas:
  sindras: {tokengroup: SINDRAS, chave: SINDRAS_KEY, datatypes: [cpf]}
EOF
}
for pr in 'env:HOME' 'env:PATH' 'env:ctvl_x_password' 'env:CTVL_SINDRAS_TOTAL' 'literal'; do
  mkpr "$pr"
  expect_rc 1 "password_ref $pr recusado" "$CTVL" check-config --file "$WORK/cfg-pr.yaml"
  has "password_ref" "mensagem cita password_ref ($pr)"
done
for pr in 'env:CTVL_ADMIN_PASSWORD' 'env:CTVL_ADMIN_PASSWORD_S7' 'env:CTVL_ADMIN_X_PASSWORD_Y' 'env:CTVL_LOGIN_PASSWORD'; do
  mkpr "$pr"
  expect_rc 1 "password_ref de credencial admin/login recusado ($pr)" "$CTVL" check-config --file "$WORK/cfg-pr.yaml"
  has "ADMIN/login|inválida" "motivo explícito ($pr)"
done
mkpr 'env:CTVL_SINDRAS_TOTAL_PASSWORD'
expect_rc 0 "password_ref válido aceito" "$CTVL" check-config --file "$WORK/cfg-pr.yaml"
PWV="$(rnd)"
OUT="$(env CTVL_SINDRAS_TOTAL_PASSWORD="$PWV" "$CTVL" plan --offline --empty-state --file "$WORK/cfg-pr.yaml" 2>&1)"
has "senha via variável CTVL_SINDRAS_TOTAL_PASSWORD \(definida" "plano mostra o NOME da variável de senha"
hasnt "$PWV" "plano nunca mostra o valor"
OUT="$(env -u CTVL_SINDRAS_TOTAL_PASSWORD "$CTVL" plan --offline --empty-state --file "$WORK/cfg-pr.yaml" 2>&1)"
has "CTVL_SINDRAS_TOTAL_PASSWORD \(NÃO definida" "plano mostra o nome também quando falta"
cat >"$WORK/cfg-pr-flat.yaml" <<'EOF'
versao: 1
recursos:
  usuarios: [{nome: sindras_cpf_total, email: a@example.invalid, password_ref: "env:CTVL_ADMIN_PASSWORD"}]
EOF
expect_rc 1 "password_ref admin recusado também na forma plana" "$CTVL" check-config --file "$WORK/cfg-pr-flat.yaml"
cat >"$WORK/cfg-admin.yaml" <<'EOF'
versao: 1
recursos:
  usuarios: [{nome: admin, email: a@example.invalid}]
EOF
expect_rc 0 "usuário 'admin' (variável derivada = senha admin) ainda carrega" "$CTVL" check-config --file "$WORK/cfg-admin.yaml"
expect_rc 0 "plan: criar o usuário 'admin' com a senha admin é BLOQUEADO" "$CTVL" plan --offline --empty-state --file "$WORK/cfg-admin.yaml"
has "BLOQUEADO +usuário +admin.*ADMIN/login" "CRIAR de usuário cuja senha seria a admin é bloqueado"

echo "-- 7.3 cache do JWT preso ao host e ao usuário"
start_fake name "$WORK/seed-id.json"; PA="$FAKE_PORT"
start_fake name "$WORK/seed-id.json"; PB="$FAKE_PORT"
printf 'sw.HOST=127.0.0.1:%s\nsw.SCHEME=http\nsw.ADMIN_USER=fakeadmin\nsw.ADMIN_PASSWORD=%s\n' "$PA" "$ADMIN_PW" >>"$CTVL_CREDENTIALS_FILE"
expect_rc 0 "token no host A" "$CTVL" token sw
expect_rc 0 "segundo token reaproveita o cache" "$CTVL" token sw
OUT="$(stats "$PA")"
has '"logins": 1' "host A viu um único login (cache reaproveitado com o mesmo host+usuário)"
BIND="$XDG_CACHE_HOME/ctvl-api/sw.jwt.bind"
if [ -f "$BIND" ] && [ "$(stat -c %a "$BIND")" = "600" ] && grep -Eq '^[0-9a-f]{64}$' "$BIND"; then ok "selo do cache: hash em modo 600"; else bad "selo do cache ausente ou fora do formato"; fi
if grep -rq "127\.0\.0\.1" "$XDG_CACHE_HOME/ctvl-api"; then bad "host em claro no cache"; else ok "cache sem o host em claro"; fi
sed -i "s/^sw\.HOST=.*/sw.HOST=127.0.0.1:$PB/" "$CTVL_CREDENTIALS_FILE"
chmod 600 "$CTVL_CREDENTIALS_FILE"
expect_rc 0 "trocar o HOST: o comando segue funcionando" "$CTVL" list sw groups
OUT="$(stats "$PB")"
has '"logins": 1' "host B viu um login novo"
has '"bad_bearer": 0' "host B nunca recebeu o JWT do host A"
sed -i "s/^sw\.ADMIN_USER=.*/sw.ADMIN_USER=outro/" "$CTVL_CREDENTIALS_FILE"
expect_rc 1 "trocar o usuário admin não reaproveita o token (tenta novo login)" "$CTVL" token sw
sed -i "s/^sw\.ADMIN_USER=.*/sw.ADMIN_USER=fakeadmin/" "$CTVL_CREDENTIALS_FILE"
chmod 600 "$CTVL_CREDENTIALS_FILE"
expect_rc 0 "token volta a funcionar com o usuário certo" "$CTVL" token sw
cp "$XDG_CACHE_HOME/ctvl-api/sw.jwt" "$WORK/old.jwt"
rm -f "$BIND"
expect_rc 0 "cache legado sem selo é descartado (novo login)" "$CTVL" token sw
OUT="$(stats "$PB")"
has '"logins": 3' "o cache sem selo gerou novo login"
PTY_SETUP_PASSWORD="$ADMIN_PW" python3 -B "$TESTS_DIR/pty_setup_env.py" "$SKILL_DIR/scripts/ctvl-setup-env.sh" sw "127.0.0.1:$PB" fakeadmin - - /api >"$WORK/setup-sw.out" 2>&1
rc=$?
OUT="$(cat "$WORK/setup-sw.out")"
if [ "$rc" -eq 0 ]; then ok "setup-env roda sob pseudo-terminal"; else bad "setup-env sob pty (rc=$rc)" "$OUT"; fi
if [ ! -e "$XDG_CACHE_HOME/ctvl-api/sw.jwt" ] && [ ! -e "$XDG_CACHE_HOME/ctvl-api/sw.jwt.bind" ]; then ok "setup-env invalida o cache do apelido"; else bad "setup-env não removeu o cache do JWT"; fi
hasnt "$ADMIN_PW" "setup-env não ecoa a senha"

echo "-- 7.4 TLS inseguro só em lista explícita de apelidos"
for a in prod prd2 producao hml; do
  printf '%s.HOST=127.0.0.1:1\n%s.ADMIN_USER=u\n%s.ADMIN_PASSWORD=%s\n%s.INSECURE_TLS=1\n' "$a" "$a" "$a" "$(rnd)" "$a" >>"$CTVL_CREDENTIALS_FILE"
done
printf 'hml.TIER=prod\n' >>"$CTVL_CREDENTIALS_FILE"
for a in prod prd2 producao hml; do
  expect_rc 1 "INSECURE_TLS recusado em '$a'" "$CTVL" token "$a"
  has "TLS inseguro é proibido no ambiente $a" "mensagem para '$a'"
done
printf 'dev.HOST=127.0.0.1:1\ndev.ADMIN_USER=u\ndev.ADMIN_PASSWORD=%s\ndev.INSECURE_TLS=1\n' "$(rnd)" >>"$CTVL_CREDENTIALS_FILE"
printf 'qa.HOST=127.0.0.1:1\nqa.ADMIN_USER=u\nqa.ADMIN_PASSWORD=%s\nqa.INSECURE_TLS=1\nqa.TIER=nonprod\n' "$(rnd)" >>"$CTVL_CREDENTIALS_FILE"
for a in dev qa; do
  expect_rc 1 "INSECURE_TLS aceito em '$a' (só falha de conexão)" "$CTVL" token "$a"
  hasnt "proibido" "'$a' passa pela checagem de TLS"
  has "falha de (conexão|rede)" "'$a' chegou até a tentativa de login"
done
printf 'tx.HOST=127.0.0.1:1\ntx.TIER=quase\n' >>"$CTVL_CREDENTIALS_FILE"
expect_rc 1 "TIER inválido é recusado" "$CTVL" token tx
has "TIER de 'tx'" "mensagem do TIER inválido"
PTY_SETUP_PASSWORD="$(rnd)" python3 -B "$TESTS_DIR/pty_setup_env.py" "$SKILL_DIR/scripts/ctvl-setup-env.sh" prd2 h.example u - - /api >"$WORK/setup-prd2.out" 2>&1
OUT="$(cat "$WORK/setup-prd2.out")"
hasnt "verificação TLS" "setup-env não oferece desligar TLS em 'prd2'"
PTY_SETUP_PASSWORD="$(rnd)" python3 -B "$TESTS_DIR/pty_setup_env.py" "$SKILL_DIR/scripts/ctvl-setup-env.sh" dev h.example u - s /api >"$WORK/setup-dev.out" 2>&1
OUT="$(cat "$WORK/setup-dev.out")"
has "verificação TLS" "setup-env oferece desligar TLS em 'dev'"
if grep -q '^dev\.INSECURE_TLS=1$' "$CTVL_CREDENTIALS_FILE"; then ok "setup-env grava INSECURE_TLS=1 em dev quando pedido"; else bad "dev sem INSECURE_TLS=1"; fi
PTY_SETUP_PASSWORD="$(rnd)" python3 -B "$TESTS_DIR/pty_setup_env.py" "$SKILL_DIR/scripts/ctvl-setup-env.sh" qa h.example u - n /api >"$WORK/setup-qa.out" 2>&1
OUT="$(cat "$WORK/setup-qa.out")"
has "verificação TLS" "setup-env oferece desligar TLS em apelido com TIER=nonprod"
if grep -q '^qa\.TIER=nonprod$' "$CTVL_CREDENTIALS_FILE"; then ok "setup-env preserva o TIER do apelido"; else bad "TIER perdido pelo setup-env"; fi

echo "-- 7.5 senha admin por ambiente (CTVL_ADMIN_PASSWORD_<AMB>) e fora do motor"
printf 's7-b.HOST=127.0.0.1:%s\ns7-b.SCHEME=http\ns7-b.ADMIN_USER=fakeadmin\ns7-b.ADMIN_PASSWORD=%s\n' "$P7" "$ADMIN_PW" >>"$CTVL_CREDENTIALS_FILE"
printf 's7-c.HOST=127.0.0.1:%s\ns7-c.SCHEME=http\ns7-c.ADMIN_USER=fakeadmin\n' "$P7" >>"$CTVL_CREDENTIALS_FILE"
WRONG="$(rnd)"
expect_rc 1 "CTVL_ADMIN_PASSWORD_S7 vale para o apelido s7 (e prevalece sobre o arquivo)" env CTVL_ADMIN_PASSWORD_S7="$WRONG" "$CTVL" token s7 --refresh
expect_rc 0 "a variável do s7 NÃO é enviada no login do s7-b" env CTVL_ADMIN_PASSWORD_S7="$WRONG" "$CTVL" token s7-b --refresh
expect_rc 1 "CTVL_ADMIN_PASSWORD_S7_B vale para s7-b (hífen vira _)" env CTVL_ADMIN_PASSWORD_S7_B="$WRONG" "$CTVL" token s7-b --refresh
expect_rc 0 "variável por ambiente com a senha certa faz login" env CTVL_ADMIN_PASSWORD_S7_C="$ADMIN_PW" "$CTVL" token s7-c --refresh
expect_rc 0 "a variável global é ignorada (vale a senha do arquivo)" env CTVL_ADMIN_PASSWORD="$WRONG" "$CTVL" token s7 --refresh
has "aposentada e é IGNORADA.*CTVL_ADMIN_PASSWORD_S7" "aviso de depreciação cita o nome da variável nova"
hasnt "$WRONG" "o aviso não imprime o valor"
expect_rc 1 "a variável global não serve de senha quando o arquivo não tem" env CTVL_ADMIN_PASSWORD="$ADMIN_PW" "$CTVL" token s7-d
cat >"$WORK/envdump.py" <<'EOF'
import os, sys
print("ADMIN_VARS:", ",".join(sorted(k for k in os.environ if k.startswith("CTVL_ADMIN_PASSWORD"))) or "nenhuma")
print("LOGIN_VAR_VISIVEL:", "CTVL_LOGIN_PASSWORD" in os.environ)
EOF
OUT="$(CTVL_ADMIN_PASSWORD=x CTVL_ADMIN_PASSWORD_DEV=y CTVL_ADMIN_PASSWORD_S7=z bash -c 'source "$1"; CTVLAPI_CORE="$2"; ctvl_py_conn plan; env | grep -c "^CTVL_ADMIN_PASSWORD"' _ "$SKILL_DIR/scripts/lib-ctvl.sh" "$WORK/envdump.py" 2>&1)"
has "ADMIN_VARS: nenhuma" "o motor Python não enxerga nenhuma CTVL_ADMIN_PASSWORD*"
has "^3$" "só o filho é limpo: o shell do usuário mantém as variáveis"
OUT="$(CTVL_ADMIN_PASSWORD=x CTVL_ADMIN_PASSWORD_DEV=y bash -c 'source "$1"; CTVLAPI_CORE="$2"; ctvl_dispatch --offline plan' _ "$SKILL_DIR/scripts/lib-ctvl.sh" "$WORK/envdump.py" 2>&1)"
has "ADMIN_VARS: nenhuma" "o modo --offline também limpa as variáveis"
OUT="$(CTVL_LOGIN_USER=u CTVL_LOGIN_PASSWORD=p bash -c 'source "$1"; CTVLAPI_CORE="$2"; ctvl_py_conn login' _ "$SKILL_DIR/scripts/lib-ctvl.sh" "$WORK/envdump.py" 2>&1)"
has "LOGIN_VAR_VISIVEL: True" "o login continua recebendo a senha pelo ambiente do filho"

echo "-- 7.6 export <-> plan: permissões sem chave ou sobre asymkey/opaqueobj"
cp -r "$TESTS_DIR/fixtures" "$WORK/fx6"
python3 - "$WORK/fx6" "$WORK/fx6-shuf" <<'EOF'
import json, os, random, sys
src, dst = sys.argv[1], sys.argv[2]
f = os.path.join(src, "permissions__token__users.json")
d = json.load(open(f))
d["results"] += [
    {"id": 10, "user": "settorj_cns", "key": "", "asymkey": "", "opaqueobj": "", "canPost": True, "canGet": True},
    {"id": 11, "user": "settorj_cns", "key": None, "asymkey": "ASYM_Z", "opaqueobj": "", "canPost": False, "canGet": True},
    {"id": 12, "user": "settorj_cns", "key": None, "asymkey": "ASYM_A", "opaqueobj": "", "canPost": False, "canGet": True},
    {"id": 13, "user": "settorj_cns", "key": "SETTORJ_KEY", "asymkey": "ASYM_K", "opaqueobj": "", "canPost": True, "canGet": True},
    {"id": 14, "user": "sindras_cns_3_left", "key": "", "asymkey": "", "opaqueobj": "OBJ_1", "canPost": True, "canGet": False},
]
d["count"] = len(d["results"])
json.dump(d, open(f, "w"))
g = os.path.join(src, "permissions__token__groups.json")
dg = json.load(open(g))
dg["results"] = [{"id": 1, "group": "app_sindras", "key": "", "asymkey": "ASYM_G", "opaqueobj": "", "canPost": False, "canGet": True}]
dg["count"] = 1
json.dump(dg, open(g, "w"))
os.makedirs(dst)
random.seed(11)
for n in os.listdir(src):
    x = json.load(open(os.path.join(src, n)))
    random.shuffle(x["results"])
    json.dump(x, open(os.path.join(dst, n), "w"))
EOF
python3 -B "$CORE" export --state-dir "$WORK/fx6" --ambiente teste --out "$WORK/e6a.yaml" 2>/dev/null
python3 -B "$CORE" export --state-dir "$WORK/fx6-shuf" --ambiente teste --out "$WORK/e6b.yaml" 2>/dev/null
if cmp -s "$WORK/e6a.yaml" "$WORK/e6b.yaml"; then ok "export com permissões ignoradas é estável byte a byte (ordem embaralhada)"; else bad "export com permissões ignoradas não é estável" "$(diff "$WORK/e6a.yaml" "$WORK/e6b.yaml")"; fi
OUT="$(cat "$WORK/e6a.yaml")"
has "^  ignorados:" "export traz a seção informativa 'ignorados'"
has "asymkey: ASYM_A" "permissão sobre asymkey listada como informativa"
has "opaqueobj: OBJ_1" "permissão sobre opaqueobj listada como informativa"
python3 - "$WORK/e6a.yaml" <<'EOF'
import sys, yaml
r = yaml.safe_load(open(sys.argv[1]))["recursos"]
assert all(p.get("chave") and "asymkey" not in p and "opaqueobj" not in p for p in r["permissoes_usuarios"]), "item aplicável com asymkey/sem chave"
ign = r["ignorados"]["permissoes_usuarios"]
assert len(ign) == 5 and len(r["ignorados"]["permissoes_grupos"]) == 1 and r["permissoes_grupos"] == []
keys = [(p["usuario"], str(p.get("chave") or ""), p.get("asymkey") or "", p.get("opaqueobj") or "") for p in ign]
assert keys == sorted(keys), keys
EOF
if [ $? -eq 0 ]; then ok "só permissões sobre chave são aplicáveis; as demais ficam ordenadas em 'ignorados'"; else bad "estrutura do export com permissões ignoradas"; fi
expect_rc 0 "check-config do export com ignorados" "$CTVL" check-config --file "$WORK/e6a.yaml"
has "AVISO: recursos.ignorados: 6 permissão" "o loader avisa em uma linha curta e ignora"
expect_rc 0 "plan do export contra o mesmo estado" "$CTVL" plan --offline --state-dir "$WORK/fx6" --file "$WORK/e6a.yaml"
hasnt "CRIAR|ATUALIZAR|CONFLITO|BLOQUEADO|ERRO" "round-trip export -> plan sem erro e idempotente (com ignorados)"
cat >"$WORK/legacy.yaml" <<'EOF'
versao: 1
recursos:
  chaves: [{nome: K1}]
  usuarios: [{nome: u1, email: a@example.invalid}]
  permissoes_usuarios:
    - {usuario: u1, chave: null, tokenize: true, detokenize: true}
    - {usuario: u1, chave: K1, asymkey: A1, tokenize: true, detokenize: true}
    - {usuario: u1, chave: K1, tokenize: true, detokenize: false}
EOF
expect_rc 0 "export antigo (chave nula / asymkey nas permissões) ainda carrega" "$CTVL" check-config --file "$WORK/legacy.yaml"
has "permissoes_usuarios +1 +u1@K1" "só a permissão sobre chave é mantida"
has "2 permissão\(ões\) sem chave ou sobre asymkey" "aviso curto sobre as ignoradas"
cat >"$WORK/typo.yaml" <<'EOF'
versao: 1
recursos:
  permissoes_usuarios: [{usuario: u1, tokenize: true}]
EOF
expect_rc 1 "permissão sem 'chave' nem 'tokengroup' escrita à mão continua sendo erro" "$CTVL" check-config --file "$WORK/typo.yaml"
EXPORT_DEV=/home/samuel.dias/dev/sindras/docs/tokenizacao-ctvl/export-dev.yaml
if [ -f "$EXPORT_DEV" ]; then
  expect_rc 0 "check-config offline sobre o export-dev.yaml real" "$CTVL" check-config --file "$EXPORT_DEV"
  has "configuração válida" "export-dev.yaml é aceito"
  expect_rc 0 "plan offline sobre o export-dev.yaml real" "$CTVL" plan --offline --empty-state --file "$EXPORT_DEV"
fi

echo "== 8. segunda rodada (re-revisão)"
REFS_ALL='tokengroup.key: name, template.tenant: name, template.format: name, template.charset: name, user.groups: name, perm_user.key: name'
new_server() { # <apelido> -> servidor falso vazio (ou com seed $2) registrado no arquivo de credenciais
  start_fake name "${2:-$WORK/seed-id.json}"
  printf '%s.HOST=127.0.0.1:%s\n%s.SCHEME=http\n%s.ADMIN_USER=fakeadmin\n%s.ADMIN_PASSWORD=%s\n' \
    "$1" "$FAKE_PORT" "$1" "$1" "$1" "$ADMIN_PW" >>"$CTVL_CREDENTIALS_FILE"
}
export CTVL_SINDRAS_CPF_TOTAL_PASSWORD="$(rnd)" CTVL_SINDRAS_SVC_TOKENIZE_PASSWORD="$(rnd)" CTVL_SINDRAS_CPF_3_LEFT_2_RIGHT_PASSWORD="$(rnd)"

echo "-- 8.N1 evidência inconclusiva de tokengroup.key: a permissão não é concedida (fail-closed)"
new_server s8
"$CTVL" admin s8 POST /keys/ --body '{"name":"1"}' --yes >/dev/null 2>&1
"$CTVL" admin s8 POST /keys/ --body '{"name":"SETTORJ_KEY"}' --yes >/dev/null 2>&1
"$CTVL" admin s8 POST /tokengroups/ --body '{"name":"SINDRAS","key":"1"}' --yes >/dev/null 2>&1
sed 's/tokengroup.key: name, //' "$WORK/cfg-conf.yaml" >"$WORK/cfg-n1.yaml"
expect_rc 0 "plan com evidência inconclusiva" "$CTVL" plan s8 --file "$WORK/cfg-n1.yaml"
has "OK +tokengroup +SINDRAS +chave não comparada" "premissa: o tokengroup sai OK sem comparar a chave"
has "BLOQUEADO +perm.usuário +sindras_cpf_total@SETTORJ_KEY.*não comparável.*api.refs.tokengroup.key" "permissão BLOQUEADA com a instrução de declarar api.refs"
OUT="$("$CTVL" apply s8 --file "$WORK/cfg-n1.yaml" --yes 2>&1)"; rc=$?
if [ "$rc" -eq 3 ]; then ok "apply --yes sem --skip-blocked aborta (rc 3)"; else bad "N1 apply sem skip (rc=$rc)" "$OUT"; fi
hasnt "EXECUTA" "nada foi escrito no abort"
OUT="$("$CTVL" apply s8 --file "$WORK/cfg-n1.yaml" --yes --skip-blocked --no-verify 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "apply --yes --skip-blocked"; else bad "N1 apply --skip-blocked (rc=$rc)" "$OUT"; fi
hasnt "EXECUTA +POST /(users|permissions)" "zero escrita de usuário/permissão com --skip-blocked"
OUT="$("$CTVL" admin s8 GET /users/ --all 2>&1)"
hasnt "sindras_" "o vault não ganhou usuário"
OUT="$("$CTVL" admin s8 GET /permissions/token/users/ --all 2>&1)"
hasnt "SETTORJ_KEY|sindras" "o vault não ganhou permissão sobre a chave de outro sistema"

echo "-- 8.N2 tokengroup novo com chave já usada por outro: bloqueia, salvo opt-in nomeado"
new_server s9
"$CTVL" admin s9 POST /keys/ --body '{"name":"SETTORJ_KEY"}' --yes >/dev/null 2>&1
"$CTVL" admin s9 POST /tokengroups/ --body '{"name":"SETTORJ","key":"SETTORJ_KEY"}' --yes >/dev/null 2>&1
mkn2() {
  cat >"$WORK/cfg-n2.yaml" <<EOF
versao: 1
convencao: {sistemas: [sindras], datatypes: [cpf]}
api:
  refs: {$REFS_ALL}
usuarios_padrao: {email_dominio: example.invalid}
recursos:
  chaves: [{nome: SETTORJ_KEY}]
defaults:
  datatypes:
    cpf:
      template: {format: FPE, charset: Numeric, keep_left: 3, keep_right: 2}
      usuarios:
        - {esquema: total, permissoes: [detokenize]}
  servico:
    - {esquema: tokenize, permissoes: [tokenize]}
sistemas:
  sindras: {tokengroup: SINDRAS_NOVO, chave: SETTORJ_KEY, datatypes: [cpf]$1}
EOF
}
mkn2 ""
expect_rc 0 "plan: SINDRAS_NOVO com a chave do SETTORJ" "$CTVL" plan s9 --file "$WORK/cfg-n2.yaml"
has "BLOQUEADO +tokengroup +SINDRAS_NOVO +chave 'SETTORJ_KEY' já é usada pelo\(s\) tokengroup\(s\) SETTORJ.*chave_compartilhada" "tokengroup novo com chave alheia é BLOQUEADO"
has "BLOQUEADO +perm.usuário +sindras_cpf_total@SETTORJ_KEY" "permissão também"
OUT="$("$CTVL" apply s9 --file "$WORK/cfg-n2.yaml" --yes --skip-blocked --no-verify 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "apply --skip-blocked sem opt-in"; else bad "N2 apply sem opt-in (rc=$rc)" "$OUT"; fi
hasnt "EXECUTA +POST /(tokengroups|tokentemplates|users|permissions)" "sem opt-in: nenhum tokengroup/template/usuário/permissão criado"
mkn2 ", chave_compartilhada: true"
OUT="$("$CTVL" apply s9 --file "$WORK/cfg-n2.yaml" --yes 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "com 'chave_compartilhada: true' o apply cria tudo"; else bad "N2 apply com opt-in (rc=$rc)" "$OUT"; fi
has "EXECUTA +POST /tokengroups/" "tokengroup criado com o opt-in"
has "EXECUTA +POST /permissions/token/users/" "permissão criada com o opt-in"
has "0 ação" "replanejamento sem pendências"
cat >"$WORK/cfg-n2-flat.yaml" <<EOF
versao: 1
api:
  refs: {$REFS_ALL}
recursos:
  chaves: [{nome: SETTORJ_KEY}]
  tokengroups: [{nome: OUTRO_TG, chave: SETTORJ_KEY, chave_compartilhada: "sim"}]
EOF
expect_rc 1 "chave_compartilhada precisa ser booleano" "$CTVL" check-config --file "$WORK/cfg-n2-flat.yaml"

echo "-- 8.N3 máscara pendente: permissão nasce sem detokenize"
new_server s10
"$CTVL" admin s10 POST /keys/ --body '{"name":"SINDRAS_KEY"}' --yes >/dev/null 2>&1
cat >"$WORK/cfg-mask.yaml" <<EOF
versao: 1
convencao: {sistemas: [sindras], datatypes: [cpf]}
api:
  refs: {$REFS_ALL}
usuarios_padrao: {email_dominio: example.invalid}
recursos:
  chaves: [{nome: SINDRAS_KEY}]
defaults:
  datatypes:
    cpf:
      template: {format: FPE, charset: Numeric, keep_left: 3, keep_right: 2}
      mascaras: {3_left_2_right: {show_left: 3, show_right: 2, mask_char: "*"}}
      usuarios:
        - {esquema: total, permissoes: [detokenize]}
        - {esquema: 3_left_2_right, permissoes: [detokenize]}
  servico:
    - {esquema: tokenize, permissoes: [tokenize]}
sistemas:
  sindras: {tokengroup: SINDRAS, chave: SINDRAS_KEY, datatypes: [cpf]}
EOF
expect_rc 0 "plan: usuário novo com máscara" "$CTVL" plan s10 --file "$WORK/cfg-mask.yaml"
has "CRIAR +perm.usuário +sindras_cpf_3_left_2_right@SINDRAS_KEY.*perfil mascarado: canGet=false.*enable-detokenize" "plano explica o canGet=false"
has "atribuir a máscara 'cpf_3_left_2_right' \(campo 'mask'" "plano lista a atribuição manual da máscara"
has "HABILITAR DETOKENIZE pendente: rode .ctvl enable-detokenize <ambiente> sindras_cpf_3_left_2_right" "plano lista o enable-detokenize pendente"
OUT="$("$CTVL" apply s10 --file "$WORK/cfg-mask.yaml" --yes 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "apply com máscara pendente"; else bad "N3 apply (rc=$rc)" "$OUT"; fi
has "3_left_2_right@SINDRAS_KEY\) +corpo=.*'canGet': False" "perm do usuário mascarado criada com canGet=false"
has "cpf_total@SINDRAS_KEY\) +corpo=.*'canGet': True" "usuário sem máscara declarada mantém canGet=true"
if [ "$(printf '%s\n' "$OUT" | grep -c 'HABILITAR DETOKENIZE pendente')" -ge 2 ]; then ok "pendência listada no plano e no resumo do apply"; else bad "pendência ausente do resumo do apply" "$OUT"; fi
OUT="$("$CTVL" admin s10 GET /permissions/token/users/ --all 2>/dev/null)"
if printf '%s' "$OUT" | python3 -c '
import json, sys
rows = {r["user"]: r for r in json.load(sys.stdin)}
assert rows["sindras_cpf_3_left_2_right"]["canGet"] is False and rows["sindras_cpf_total"]["canGet"] is True'; then ok "vault: canGet=false só no perfil mascarado"; else bad "estado das permissões no vault" "$OUT"; fi
expect_rc 0 "plan seguinte (máscara ainda não atribuída)" "$CTVL" plan s10 --file "$WORK/cfg-mask.yaml"
hasnt "ATUALIZAR +perm" "sem máscara atribuída o plano não propõe habilitar canGet"
has "HABILITAR DETOKENIZE pendente" "a pendência continua listada"
printf '{"users": [{"username": "sindras_cpf_3_left_2_right", "password": "%s", "mask": "cpf_3_left_2_right"}]}' "$(rnd)" >"$WORK/seed-mask.json"
new_server s11 "$WORK/seed-mask.json"
"$CTVL" admin s11 POST /masks/ --body '{"name":"cpf_3_left_2_right","showleft":3,"showright":2,"maskchar":"*"}' --yes >/dev/null 2>&1
"$CTVL" admin s11 POST /keys/ --body '{"name":"SINDRAS_KEY"}' --yes >/dev/null 2>&1
"$CTVL" admin s11 POST /tokengroups/ --body '{"name":"SINDRAS","key":"SINDRAS_KEY"}' --yes >/dev/null 2>&1
"$CTVL" admin s11 POST /permissions/token/users/ --body '{"user":"sindras_cpf_3_left_2_right","key":"SINDRAS_KEY","canPost":false,"canGet":false}' --yes >/dev/null 2>&1
expect_rc 0 "plan: máscara já atribuída no vault" "$CTVL" plan s11 --file "$WORK/cfg-mask.yaml"
has "OK +usuário +sindras_cpf_3_left_2_right" "usuário com a máscara certa está OK"
hasnt "ATUALIZAR +perm.usuário +sindras_cpf_3_left_2_right" "mesmo com a máscara certa, o plano NUNCA propõe subir o canGet do perfil mascarado"
has "HABILITAR DETOKENIZE pendente: rode .ctvl enable-detokenize <ambiente> sindras_cpf_3_left_2_right" "o caminho é o enable-detokenize"

echo "-- 8.N8 apelidos que colidem na variável de senha"
printf 'x-y.HOST=127.0.0.1:1\nx_y.HOST=127.0.0.1:1\n' >"$WORK/cred-coll"
chmod 600 "$WORK/cred-coll"
expect_rc 1 "apelido x-y recusado quando x_y existe" env CTVL_CREDENTIALS_FILE="$WORK/cred-coll" "$CTVL" token x-y
has "colidem na variável de senha CTVL_ADMIN_PASSWORD_X_Y" "mensagem cita as duas e a variável"
expect_rc 1 "apelido x_y também" env CTVL_CREDENTIALS_FILE="$WORK/cred-coll" "$CTVL" token x_y
OUT="$(env CTVL_CREDENTIALS_FILE="$WORK/cred-coll" "$CTVL" setup-env x-y </dev/null 2>&1)"; rc=$?
if [ "$rc" -eq 1 ]; then ok "setup-env também recusa o apelido que colide"; else bad "setup-env colisão (rc=$rc)" "$OUT"; fi
has "colidem" "setup-env explica a colisão"

echo "== 9. terceira rodada (re-revisão 2)"
REFS_G="$REFS_ALL, perm_group.group: name, perm_group.key: name"
post() { "$CTVL" admin "$1" POST "$2" --body "$3" --yes >/dev/null 2>&1; }

echo "-- 9.1 máscara pendente também quando difere da declarada ou não resolve"
cp -r "$TESTS_DIR/fixtures" "$WORK/fx-wrong"
cp -r "$TESTS_DIR/fixtures" "$WORK/fx-unres"
cp -r "$TESTS_DIR/fixtures" "$WORK/fx-ok"
python3 - "$WORK" <<'EOF'
import json, os, sys
w = sys.argv[1]
def edit(d, name, fn):
    f = os.path.join(w, d, name)
    x = json.load(open(f))
    fn(x["results"])
    json.dump(x, open(f, "w"))
def set_mask(rows):
    for u in rows:
        if u["username"] == "sindras_cns_3_left":
            u["mask"] = "legacy_mask"
edit("fx-wrong", "users.json", set_mask)
edit("fx-unres", "masks.json", lambda rows: rows.clear())
def perm_false(rows):
    for r in rows:
        if r["user"] == "sindras_cns_3_left":
            r["canGet"] = False
edit("fx-ok", "permissions__token__users.json", perm_false)
EOF
expect_rc 0 "plan: máscara DIFERENTE atribuída (mostra tudo) não promove o detokenize" "$CTVL" plan --offline --state-dir "$WORK/fx-wrong" --file "$WORK/e1.yaml"
has "MANUAL +usuário +sindras_cns_3_left" "usuário com outra máscara é MANUAL"
has "ATUALIZAR +perm.usuário +sindras_cns_3_left@SINDRAS_KEY" "a permissão é rebaixada"
hasnt "False' -> True|: False -> True" "nunca propõe canGet false -> true"
has "a máscara atual 'legacy_mask' difere da declarada 'cns_3_left'" "mensagem clara: máscara atual difere da declarada"
OUT="$("$CTVL" plan --offline --state-dir "$WORK/fx-wrong" --file "$WORK/e1.yaml" 2>&1 | grep -A1 'perm.usuário  *sindras_cns_3_left@SINDRAS_KEY')"
has "True -> False" "rebaixa canGet true -> false"
expect_rc 0 "plan: referência de máscara não resolvida" "$CTVL" plan --offline --state-dir "$WORK/fx-unres" --file "$WORK/e1.yaml"
has "não pôde ser resolvida" "mensagem: máscara não resolvida"
OUT="$("$CTVL" plan --offline --state-dir "$WORK/fx-unres" --file "$WORK/e1.yaml" 2>&1 | grep -A1 'perm.usuário  *sindras_cns_3_left@SINDRAS_KEY')"
has "ATUALIZAR.*sindras_cns_3_left@SINDRAS_KEY" "permissão rebaixada com referência não resolvida"
has "True -> False" "canGet true -> false (fail-closed)"
expect_rc 0 "plan: máscara correta e canGet=false no vault" "$CTVL" plan --offline --state-dir "$WORK/fx-ok" --file "$WORK/e1.yaml"
OUT="$("$CTVL" plan --offline --state-dir "$WORK/fx-ok" --file "$WORK/e1.yaml" 2>&1)"
hasnt "ATUALIZAR.*sindras_cns_3_left@SINDRAS_KEY|False -> True" "máscara correta: o plan não sobe o canGet (só o enable-detokenize)"
has "HABILITAR DETOKENIZE pendente" "máscara correta: lista o enable-detokenize pendente"
python3 - "$WORK/seed-mask.json" "$WORK/seed-wrong.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
d["users"][0]["mask"] = "cpf_aberta"
json.dump(d, open(sys.argv[2], "w"))
EOF
new_server s13 "$WORK/seed-wrong.json"
post s13 /keys/ '{"name":"SINDRAS_KEY"}'
post s13 /tokengroups/ '{"name":"SINDRAS","key":"SINDRAS_KEY"}'
post s13 /masks/ '{"name":"cpf_aberta","showleft":11,"showright":0,"maskchar":"*"}'
post s13 /permissions/token/users/ '{"user":"sindras_cpf_3_left_2_right","key":"SINDRAS_KEY","canPost":false,"canGet":true}'
expect_rc 0 "plan ao vivo: usuário com a máscara aberta e canGet=true" "$CTVL" plan s13 --file "$WORK/cfg-mask.yaml"
has "a máscara atual 'cpf_aberta' difere da declarada 'cpf_3_left_2_right'" "plano ao vivo explica a divergência"
OUT="$("$CTVL" apply s13 --file "$WORK/cfg-mask.yaml" --yes 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "apply --yes com máscara errada atribuída"; else bad "9.1 apply (rc=$rc)" "$OUT"; fi
has "EXECUTA +PUT /permissions/token/users/" "a permissão é rebaixada"
OUT="$("$CTVL" admin s13 GET /permissions/token/users/ --all 2>/dev/null)"
if printf '%s' "$OUT" | python3 -c '
import json, sys
rows = {r["user"]: r for r in json.load(sys.stdin)}
assert rows["sindras_cpf_3_left_2_right"]["canGet"] is False'; then ok "vault: canGet=false para o usuário com a máscara errada"; else bad "vault ainda libera detokenize" "$OUT"; fi
expect_rc 0 "plan seguinte: continua sem promover" "$CTVL" plan s13 --file "$WORK/cfg-mask.yaml"
hasnt "False -> True" "nenhuma promoção enquanto a máscara não for a declarada"

echo "-- 9.2 mesma chave em dois tokengroups declarados (vault vazio)"
mkn9() { # <opt-in-sindras> <opt-in-biae>
  cat >"$WORK/cfg-share.yaml" <<EOF
versao: 1
convencao: {sistemas: [sindras, biae], datatypes: [cpf]}
api:
  refs: {$REFS_ALL}
usuarios_padrao: {email_dominio: example.invalid}
recursos:
  chaves: [{nome: K_COMUM}]
defaults:
  datatypes:
    cpf:
      template: {format: FPE, charset: Numeric, keep_left: 3, keep_right: 2}
      usuarios:
        - {esquema: total, permissoes: [detokenize]}
  servico:
    - {esquema: tokenize, permissoes: [tokenize]}
sistemas:
  sindras: {tokengroup: SINDRAS, chave: K_COMUM, datatypes: [cpf]$1}
  biae: {tokengroup: BIAE, chave: K_COMUM, datatypes: [cpf]$2}
EOF
}
mkn9 "" ""
expect_rc 0 "plan offline: dois sistemas com a mesma chave" "$CTVL" plan --offline --empty-state --file "$WORK/cfg-share.yaml"
has "BLOQUEADO +tokengroup +SINDRAS +chave 'K_COMUM' já é usada pelo\(s\) tokengroup\(s\) BIAE" "SINDRAS bloqueado por causa do BIAE declarado"
has "BLOQUEADO +tokengroup +BIAE +chave 'K_COMUM' já é usada pelo\(s\) tokengroup\(s\) SINDRAS" "BIAE bloqueado por causa do SINDRAS declarado"
hasnt "CRIAR +tokengroup" "nenhum tokengroup a criar sem o opt-in"
has "BLOQUEADO +perm.usuário +sindras_cpf_total@K_COMUM" "permissões também bloqueadas"
new_server s14
post s14 /keys/ '{"name":"K_COMUM"}'
OUT="$("$CTVL" apply s14 --file "$WORK/cfg-share.yaml" --yes --skip-blocked --no-verify 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "apply --skip-blocked sem opt-in"; else bad "9.2 apply (rc=$rc)" "$OUT"; fi
hasnt "EXECUTA +POST /(tokengroups|tokentemplates|users|permissions)" "primeiro apply: nada criado sobre a chave compartilhada"
mkn9 ", chave_compartilhada: true" ", chave_compartilhada: true"
export CTVL_BIAE_CPF_TOTAL_PASSWORD="$(rnd)" CTVL_BIAE_SVC_TOKENIZE_PASSWORD="$(rnd)"
OUT="$("$CTVL" apply s14 --file "$WORK/cfg-share.yaml" --yes 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "com chave_compartilhada nos dois, o apply cria tudo"; else bad "9.2 apply com opt-in (rc=$rc)" "$OUT"; fi
has "EXECUTA +POST /tokengroups/" "tokengroups criados com o opt-in"
has "EXECUTA +POST /permissions/token/users/" "permissões criadas com o opt-in"
mkn9 ", chave_compartilhada: true" ""
expect_rc 0 "plan: opt-in só em um dos dois" "$CTVL" plan --offline --empty-state --file "$WORK/cfg-share.yaml"
has "BLOQUEADO +tokengroup +BIAE" "cada tokengroup que compartilha precisa declarar o opt-in"
cat >"$WORK/cfg-share-flat.yaml" <<'EOF'
versao: 1
recursos:
  chaves: [{nome: K_S}, {nome: K_B}]
  tokengroups: [{nome: SINDRAS, chave: K_S}, {nome: BIAE, chave: K_B}]
  usuarios: [{nome: sindras_cpf_total, email: a@example.invalid}]
  permissoes_usuarios: [{usuario: sindras_cpf_total, tokengroup: SINDRAS, chave: K_B, detokenize: true}]
EOF
expect_rc 0 "plan: variante plana, permissão do SINDRAS sobre a chave do BIAE" "$CTVL" plan --offline --empty-state --file "$WORK/cfg-share-flat.yaml"
has "BLOQUEADO +perm.usuário +sindras_cpf_total@K_B +chave 'K_B' difere da chave declarada 'K_S' para o tokengroup 'SINDRAS'" "permissão sobre a chave de outro tokengroup novo é BLOQUEADA"
has "CRIAR +usuário +sindras_cpf_total +PULADO" "usuário só dessa permissão é pulado"

echo "-- 9.3 tokengroup que já existe e compartilha a chave"
new_server s15
post s15 /keys/ '{"name":"K_BIAE"}'
post s15 /tokengroups/ '{"name":"BIAE","key":"K_BIAE"}'
post s15 /tokengroups/ '{"name":"SINDRAS","key":"K_BIAE"}'
mkn3() {
  cat >"$WORK/cfg-exist.yaml" <<EOF
versao: 1
convencao: {sistemas: [sindras], datatypes: [cpf]}
api:
  refs: {$REFS_ALL}
usuarios_padrao: {email_dominio: example.invalid}
recursos:
  chaves: [{nome: K_BIAE}]
defaults:
  datatypes:
    cpf:
      template: {format: FPE, charset: Numeric, keep_left: 3, keep_right: 2}
      usuarios:
        - {esquema: total, permissoes: [detokenize]}
sistemas:
  sindras: {tokengroup: SINDRAS, chave: K_BIAE, datatypes: [cpf]$1}
EOF
}
mkn3 ""
expect_rc 0 "plan: SINDRAS já usa a chave do BIAE" "$CTVL" plan s15 --file "$WORK/cfg-exist.yaml"
has "OK +tokengroup +SINDRAS" "o tokengroup existente segue OK (estado do vault não é bloqueado)"
has "BLOQUEADO +perm.usuário +sindras_cpf_total@K_BIAE.*também é usada pelo\(s\) tokengroup\(s\) BIAE" "a permissão a criar é BLOQUEADA sem o opt-in"
has "CRIAR +usuário +sindras_cpf_total +PULADO" "e o usuário dependente é pulado"
OUT="$("$CTVL" apply s15 --file "$WORK/cfg-exist.yaml" --yes --skip-blocked --no-verify 2>&1)"; rc=$?
hasnt "EXECUTA +POST /(users|permissions)" "sem opt-in: zero escrita de usuário/permissão"
mkn3 ", chave_compartilhada: true"
OUT="$("$CTVL" apply s15 --file "$WORK/cfg-exist.yaml" --yes 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "com o opt-in o apply cria usuário e permissão"; else bad "9.3 apply com opt-in (rc=$rc)" "$OUT"; fi
has "EXECUTA +POST /permissions/token/users/" "permissão criada com o opt-in"
mkn3 ""
expect_rc 0 "plan sem o opt-in depois que a permissão já existe" "$CTVL" plan s15 --file "$WORK/cfg-exist.yaml"
hasnt "BLOQUEADO +perm" "permissão que já existe no vault não é bloqueada (só o que o YAML pede escrever)"
if [ -f "$EXPORT_DEV" ]; then
  mkdir "$WORK/fx-dev"
  python3 - "$EXPORT_DEV" "$WORK/fx-dev" <<'EOF'
import json, os, sys, yaml
r = yaml.safe_load(open(sys.argv[1]))["recursos"]
out = sys.argv[2]
def dump(name, rows):
    json.dump({"count": len(rows), "next": None, "previous": None, "results": rows}, open(os.path.join(out, name), "w"))
dump("keys.json", [{"idkey": i, "name": k["nome"], "seedkey": False} for i, k in enumerate(r["chaves"], 1)])
dump("tokengroups.json", [{"idtenant": i, "name": t["nome"], "key": t["chave"]} for i, t in enumerate(r["tokengroups"], 1)])
dump("groups.json", [{"id": i, "name": g["nome"]} for i, g in enumerate(r["grupos"], 1)])
dump("permissions__token__users.json", [{"id": i, "user": p["usuario"], "key": p["chave"], "asymkey": "", "opaqueobj": "",
                                         "canPost": p["tokenize"], "canGet": p["detokenize"]}
                                        for i, p in enumerate(r["permissoes_usuarios"], 1)])
EOF
  expect_rc 0 "plan do export-dev.yaml contra o estado (SES e defaultGroup já compartilham a chave CTS)" "$CTVL" plan --offline --state-dir "$WORK/fx-dev" --file "$EXPORT_DEV"
  hasnt "BLOQUEADO +(tokengroup|perm)|também é usada|chave_compartilhada" "o compartilhamento que já existe no vault não é bloqueado"
  has "OK +tokengroup +SES" "tokengroup SES segue OK"
  expect_rc 0 "check-config do export-dev.yaml segue passando" "$CTVL" check-config --file "$EXPORT_DEV"
fi

echo "-- 9.4 usuário com máscara pendente num grupo que concede detokenize"
cat >"$WORK/cfg-grp.yaml" <<EOF
versao: 1
convencao: {sistemas: [sindras], datatypes: [cpf]}
api:
  refs: {$REFS_G}
usuarios_padrao: {email_dominio: example.invalid}
recursos:
  chaves: [{nome: SINDRAS_KEY}]
  grupos: [{nome: g_det}]
defaults:
  datatypes:
    cpf:
      template: {format: FPE, charset: Numeric, keep_left: 3, keep_right: 2}
      mascaras: {3_left_2_right: {show_left: 3, show_right: 2, mask_char: "*"}}
      usuarios:
        - {esquema: 3_left_2_right, permissoes: [detokenize], grupos: [g_det]}
sistemas:
  sindras: {tokengroup: SINDRAS, chave: SINDRAS_KEY, datatypes: [cpf]}
EOF
cp "$WORK/cfg-grp.yaml" "$WORK/cfg-grp-decl.yaml"
python3 - "$WORK/cfg-grp-decl.yaml" <<'EOF'
import sys
p = sys.argv[1]
s = open(p).read().replace("  grupos: [{nome: g_det}]\n", "  grupos: [{nome: g_det}]\n  permissoes_grupos: [{grupo: g_det, chave: SINDRAS_KEY, tokenize: false, detokenize: true}]\n")
open(p, "w").write(s)
EOF
expect_rc 0 "plan: grupo declara detokenize e o usuário tem máscara pendente" "$CTVL" plan --offline --empty-state --file "$WORK/cfg-grp-decl.yaml"
has "CRIAR +perm.grupo +g_det@SINDRAS_KEY.*grupo com membro\(s\) mascarado\(s\) \(sindras_cpf_3_left_2_right\): canGet=false" "grupo declarado com detokenize e membro mascarado: permissão do grupo vai com canGet=false"
has "grupo g_det: a permissão do grupo fica canGet=false" "pendência do grupo listada com o nome do grupo e dos membros"
hasnt "BLOQUEADO +usuário" "o usuário nasce (o grupo não concede)"
new_server s16
post s16 /keys/ '{"name":"SINDRAS_KEY"}'
post s16 /tokengroups/ '{"name":"SINDRAS","key":"SINDRAS_KEY"}'
post s16 /groups/ '{"name":"g_det"}'
post s16 /permissions/token/groups/ '{"group":"g_det","key":"SINDRAS_KEY","canPost":false,"canGet":true}'
expect_rc 0 "plan ao vivo: o grupo já tem canGet=true no vault" "$CTVL" plan s16 --file "$WORK/cfg-grp.yaml"
has "BLOQUEADO +usuário +sindras_cpf_3_left_2_right.*já tem canGet=true no vault" "usuário BLOQUEADO (grupo atual concede detokenize)"
OUT="$("$CTVL" apply s16 --file "$WORK/cfg-grp.yaml" --yes --skip-blocked --no-verify 2>&1)"; rc=$?
hasnt "EXECUTA +POST /users/" "nenhum usuário criado dentro do grupo com canGet=true"
OUT="$("$CTVL" admin s16 GET /users/ --all 2>&1)"
hasnt "sindras_cpf_3_left_2_right" "o vault não ganhou o usuário"
new_server s17
post s17 /keys/ '{"name":"SINDRAS_KEY"}'
post s17 /tokengroups/ '{"name":"SINDRAS","key":"SINDRAS_KEY"}'
post s17 /groups/ '{"name":"g_det"}'
post s17 /permissions/token/groups/ '{"group":"g_det","key":"SINDRAS_KEY","canPost":true,"canGet":false}'
expect_rc 0 "plan ao vivo: grupo sem canGet" "$CTVL" plan s17 --file "$WORK/cfg-grp.yaml"
has "CRIAR +usuário +sindras_cpf_3_left_2_right" "usuário é criado normalmente"
hasnt "BLOQUEADO +usuário" "sem bloqueio quando o grupo não concede detokenize"
OUT="$("$CTVL" apply s17 --file "$WORK/cfg-grp.yaml" --yes 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "apply cria o usuário no grupo sem canGet"; else bad "9.4 apply (rc=$rc)" "$OUT"; fi
has "EXECUTA +POST /users/" "usuário criado"

echo "== 10. regra única: o apply nunca escreve canGet=true para perfil mascarado"
canget() { # <apelido> <path> <campo user|group> <nome> -> true|false|ausente (canGet no vault)
  "$CTVL" admin "$1" GET "$2" --all 2>/dev/null | python3 -c '
import json, sys
rows = [r for r in json.load(sys.stdin) if r.get(sys.argv[1]) == sys.argv[2]]
print(str(rows[0]["canGet"]).lower() if rows else "ausente")' "$3" "$4"
}
PWS="$(rnd)"; PWU="$(rnd)"
MASKED=sindras_cpf_3_left_2_right
mkmask() { # <status-da-máscara|"">  -> $WORK/cfg-m.yaml (usuário mascarado + total + serviço)
  sed "s/3_left_2_right: {show_left: 3, show_right: 2, mask_char: \"\*\"}/3_left_2_right: {show_left: 3, show_right: 2, mask_char: \"*\"$1}/" "$WORK/cfg-mask.yaml" >"$WORK/cfg-m.yaml"
}
echo "-- 10.A1 máscara bloqueada/a confirmar: nenhum caminho sobe o canGet"
mkmask ", status: a_confirmar"
new_server s20 "$WORK/seed-mask.json"
post s20 /keys/ '{"name":"SINDRAS_KEY"}'
post s20 /tokengroups/ '{"name":"SINDRAS","key":"SINDRAS_KEY"}'
post s20 /masks/ '{"name":"cpf_3_left_2_right","showleft":3,"showright":2,"maskchar":"*"}'
post s20 /permissions/token/users/ '{"user":"sindras_cpf_3_left_2_right","key":"SINDRAS_KEY","canPost":false,"canGet":true}'
expect_rc 0 "plan: máscara a confirmar e perfil mascarado com canGet=true no vault" "$CTVL" plan s20 --file "$WORK/cfg-m.yaml"
has "ATUALIZAR +perm.usuário +sindras_cpf_3_left_2_right@SINDRAS_KEY" "a permissão é rebaixada"
OUT="$("$CTVL" apply s20 --file "$WORK/cfg-m.yaml" --yes --skip-blocked --no-verify 2>&1)"
OUT="$(printf '%s\n' "$OUT" | grep "EXECUTA.*$MASKED@")"
has "'canGet': False" "o corpo do perfil mascarado vai com canGet=false"
hasnt "'canGet': True" "nenhum corpo do perfil mascarado enviado com canGet=true"
if [ "$(canget s20 /permissions/token/users/ user "$MASKED")" = "false" ]; then ok "vault: canGet rebaixado para false"; else bad "10.A1 vault"; fi

echo "-- 10.A2 grupo com membro mascarado (membro só no vault) nunca recebe canGet=true"
new_server s21 "$WORK/seed-mask.json"
post s21 /keys/ '{"name":"SINDRAS_KEY"}'
post s21 /tokengroups/ '{"name":"SINDRAS","key":"SINDRAS_KEY"}'
post s21 /masks/ '{"name":"cpf_3_left_2_right","showleft":3,"showright":2,"maskchar":"*"}'
post s21 /groups/ '{"name":"g_det"}'
"$CTVL" admin s21 PUT /users/1 --body '{"username":"sindras_cpf_3_left_2_right","email":"a@example.invalid","groups":["g_det"]}' --yes >/dev/null 2>&1
cat >"$WORK/cfg-gm.yaml" <<EOF
versao: 1
api:
  refs: {$REFS_G}
recursos:
  chaves: [{nome: SINDRAS_KEY}]
  grupos: [{nome: g_det}]
  tokengroups: [{nome: SINDRAS, chave: SINDRAS_KEY}]
  permissoes_grupos: [{grupo: g_det, chave: SINDRAS_KEY, tokenize: false, detokenize: true}]
EOF
expect_rc 0 "plan: grupo declara detokenize e o único membro (só no vault) é mascarado" "$CTVL" plan s21 --file "$WORK/cfg-gm.yaml"
has "CRIAR +perm.grupo +g_det@SINDRAS_KEY.*membro\(s\) mascarado\(s\) \(sindras_cpf_3_left_2_right\): canGet=false" "permissão do grupo vai com canGet=false"
has "grupo g_det: a permissão do grupo fica canGet=false" "pendência cita o grupo"
OUT="$("$CTVL" apply s21 --file "$WORK/cfg-gm.yaml" --yes --no-verify 2>&1 | grep "EXECUTA.*g_det@")"
has "'canGet': False" "apply escreve canGet=false para o grupo"
hasnt "'canGet': True" "nenhum corpo com canGet=true"
if [ "$(canget s21 /permissions/token/groups/ group g_det)" = "false" ]; then ok "vault: permissão do grupo com canGet=false"; else bad "10.A2 vault"; fi
"$CTVL" admin s21 PUT /permissions/token/groups/1 --body '{"group":"g_det","key":"SINDRAS_KEY","canPost":false,"canGet":true}' --yes >/dev/null 2>&1
expect_rc 0 "plan: o grupo já está canGet=true no vault" "$CTVL" plan s21 --file "$WORK/cfg-gm.yaml"
has "ATUALIZAR +perm.grupo +g_det@SINDRAS_KEY" "rebaixa a permissão do grupo"
"$CTVL" apply s21 --file "$WORK/cfg-gm.yaml" --yes --no-verify >/dev/null 2>&1
if [ "$(canget s21 /permissions/token/groups/ group g_det)" = "false" ]; then ok "vault: grupo rebaixado"; else bad "10.A2 rebaixamento"; fi
cat >"$WORK/cfg-gp.yaml" <<EOF
versao: 1
api:
  refs: {$REFS_G}
recursos:
  chaves: [{nome: SINDRAS_KEY}]
  grupos: [{nome: g_ok}]
  tokengroups: [{nome: SINDRAS, chave: SINDRAS_KEY}]
  permissoes_grupos: [{grupo: g_ok, chave: SINDRAS_KEY, tokenize: false, detokenize: true}]
EOF
OUT="$("$CTVL" plan s21 --file "$WORK/cfg-gp.yaml" 2>&1)"
has "CRIAR +perm.grupo +g_ok@SINDRAS_KEY" "grupo sem membro mascarado segue como hoje"
hasnt "g_ok.*mascarado" "sem aviso de mascarado para o grupo sem membros mascarados"

echo "-- 10.M1 permissão só por chave (formato do export) em chave usada por mais de um tokengroup"
printf '{"users": [{"username": "u_flat", "password": "%s"}]}' "$(rnd)" >"$WORK/seed-flat.json"
new_server s22 "$WORK/seed-flat.json"
post s22 /keys/ '{"name":"K_SH"}'
post s22 /tokengroups/ '{"name":"TG_A","key":"K_SH"}'
post s22 /tokengroups/ '{"name":"TG_B","key":"K_SH"}'
mkflat() { # <opt-in> <tokenize> -> permissão só por chave
  cat >"$WORK/cfg-flat.yaml" <<EOF
versao: 1
api:
  refs: {$REFS_ALL}
recursos:
  chaves: [{nome: K_SH}]
  tokengroups: [{nome: TG_A, chave: K_SH$1}, {nome: TG_B, chave: K_SH$1}]
  usuarios: [{nome: u_flat, email: a@example.invalid}]
  permissoes_usuarios: [{usuario: u_flat, chave: K_SH, tokenize: $2, detokenize: false}]
EOF
}
mkflat "" true
expect_rc 0 "plan: permissão por chave compartilhada sem opt-in" "$CTVL" plan s22 --file "$WORK/cfg-flat.yaml"
has "BLOQUEADO +perm.usuário +u_flat@K_SH.*mais de um tokengroup \(TG_A, TG_B\)" "CRIAR que aumenta privilégio é BLOQUEADO"
OUT="$("$CTVL" apply s22 --file "$WORK/cfg-flat.yaml" --yes --skip-blocked --no-verify 2>&1)"
hasnt "EXECUTA +POST /permissions" "nada escrito"
mkflat ", chave_compartilhada: true" true
expect_rc 0 "plan: com opt-in nos dois tokengroups" "$CTVL" plan s22 --file "$WORK/cfg-flat.yaml"
has "CRIAR +perm.usuário +u_flat@K_SH" "com o opt-in a permissão é criada"
"$CTVL" apply s22 --file "$WORK/cfg-flat.yaml" --yes --no-verify >/dev/null 2>&1
mkflat "" false
expect_rc 0 "plan: rebaixamento (canPost true -> false) na chave compartilhada sem opt-in" "$CTVL" plan s22 --file "$WORK/cfg-flat.yaml"
has "ATUALIZAR +perm.usuário +u_flat@K_SH" "rebaixar nunca é bloqueado"
hasnt "BLOQUEADO +perm" "sem bloqueio no rebaixamento"

echo "-- 10.M2 rebaixar o canGet de perfil mascarado em chave compartilhada não é bloqueado"
new_server s23 "$WORK/seed-mask.json"
post s23 /keys/ '{"name":"K_SH"}'
post s23 /tokengroups/ '{"name":"SINDRAS","key":"K_SH"}'
post s23 /tokengroups/ '{"name":"BIAE","key":"K_SH"}'
post s23 /masks/ '{"name":"cpf_3_left_2_right","showleft":3,"showright":2,"maskchar":"*"}'
post s23 /permissions/token/users/ '{"user":"sindras_cpf_3_left_2_right","key":"K_SH","canPost":false,"canGet":true}'
cat >"$WORK/cfg-m2.yaml" <<EOF
versao: 1
api:
  refs: {$REFS_ALL}
recursos:
  chaves: [{nome: K_SH}]
  tokengroups: [{nome: SINDRAS, chave: K_SH}]
  mascaras: [{nome: cpf_3_left_2_right, show_left: 2, show_right: 2, mask_char: "*"}]
  usuarios: [{nome: sindras_cpf_3_left_2_right, email: a@example.invalid, mascara: cpf_3_left_2_right}]
  permissoes_usuarios: [{usuario: sindras_cpf_3_left_2_right, tokengroup: SINDRAS, chave: K_SH, tokenize: false, detokenize: true}]
EOF
expect_rc 0 "plan: máscara do vault difere da declarada, canGet=true, chave compartilhada" "$CTVL" plan s23 --file "$WORK/cfg-m2.yaml"
has "ATUALIZAR +perm.usuário +sindras_cpf_3_left_2_right@K_SH" "rebaixa mesmo com a chave compartilhada sem opt-in"
hasnt "BLOQUEADO +perm" "o rebaixamento não é bloqueado"
"$CTVL" apply s23 --file "$WORK/cfg-m2.yaml" --yes --skip-blocked --no-verify >/dev/null 2>&1
if [ "$(canget s23 /permissions/token/users/ user "$MASKED")" = "false" ]; then ok "vault: canGet=false"; else bad "10.M2 vault"; fi

echo "-- 10.M3 permissão só por tokengroup (chave herdada)"
new_server s24 "$WORK/seed-flat.json"
post s24 /keys/ '{"name":"K1"}'
post s24 /keys/ '{"name":"K2"}'
post s24 /tokengroups/ '{"name":"SINDRAS","key":"K1"}'
cat >"$WORK/cfg-m3.yaml" <<EOF
versao: 1
api:
  refs: {$REFS_ALL}
recursos:
  chaves: [{nome: K1}, {nome: K2}]
  tokengroups: [{nome: SINDRAS, chave: K2}]
  usuarios: [{nome: u_flat, email: a@example.invalid}]
  permissoes_usuarios: [{usuario: u_flat, tokengroup: SINDRAS, tokenize: true, detokenize: false}]
EOF
expect_rc 0 "plan: tokengroup declara K2 mas no vault usa K1; permissão herda a chave" "$CTVL" plan s24 --file "$WORK/cfg-m3.yaml"
has "CONFLITO +tokengroup +SINDRAS" "tokengroup em CONFLITO"
has "BLOQUEADO +perm.usuário +u_flat@SINDRAS.*difere da chave atual 'K1'" "permissão com chave herdada é comparada com a real"
OUT="$("$CTVL" apply s24 --file "$WORK/cfg-m3.yaml" --yes --skip-blocked --no-verify 2>&1)"
hasnt "EXECUTA +POST /permissions" "nada escrito"
new_server s25
post s25 /keys/ '{"name":"1"}'
post s25 /keys/ '{"name":"K2"}'
post s25 /tokengroups/ '{"name":"SINDRAS","key":"1"}'
sed 's/tokengroup.key: name, //' "$WORK/cfg-m3.yaml" | sed 's/chaves: \[{nome: K1}, {nome: K2}\]/chaves: [{nome: K2}]/' >"$WORK/cfg-m3b.yaml"
expect_rc 0 "plan: evidência inconclusiva em tokengroup.key" "$CTVL" plan s25 --file "$WORK/cfg-m3b.yaml"
has "BLOQUEADO +perm.usuário +u_flat@SINDRAS.*declare api.refs.tokengroup.key \(rode probe-refs\)" "mesmo com a chave herdada: bloqueia pedindo api.refs"
cat >"$WORK/cfg-deps.yaml" <<'EOF'
versao: 1
recursos:
  chaves: [{nome: K_X}]
  tokengroups: [{nome: TG_X}]
  usuarios: [{nome: u_x, email: a@example.invalid}]
  permissoes_usuarios: [{usuario: u_x, tokengroup: TG_X, chave: K_X, tokenize: true, detokenize: false}]
EOF
expect_rc 0 "plan: tokengroup bloqueado (sem chave) e permissão com chave própria" "$CTVL" plan --offline --empty-state --file "$WORK/cfg-deps.yaml"
has "BLOQUEADO +tokengroup +TG_X" "tokengroup sem chave é BLOQUEADO"
has "CRIAR +perm.usuário +u_x@K_X +PULADO: depende de tokengroup 'TG_X'" "a dependência do tokengroup leva a permissão (exercita o deps sozinho)"

echo "-- 10.B2 aviso de bloqueio no plan sem --check"
OUT="$("$CTVL" plan s24 --file "$WORK/cfg-m3.yaml" 2>&1)"
has "AVISO: .* BLOQUEADO/CONFLITO neste plano.*--check" "plan avisa que sai com 0 mesmo bloqueado"
OUT="$("$CTVL" plan s24 --file "$WORK/cfg-m3.yaml" --check 2>&1)"
hasnt "neste plano" "com --check o aviso não é necessário"

echo "-- 10.E enable-detokenize: único caminho que escreve canGet=true para perfil mascarado"
en_setup() { # <apelido> <máscara atribuída> <show_right da máscara no vault> [grupo-com-canGet-true]
  printf '{"users":[{"username":"sindras_svc_tokenize","password":"%s"},{"username":"%s","password":"%s","mask":"%s"}]}' "$PWS" "$MASKED" "$PWU" "$2" >"$WORK/seed-en-$1.json"
  new_server "$1" "$WORK/seed-en-$1.json"
  post "$1" /masks/ '{"name":"cpf_3_left_2_right","showleft":3,"showright":'"$3"',"maskchar":"*"}'
  post "$1" /masks/ '{"name":"cpf_aberta","showleft":11,"showright":0,"maskchar":"*"}'
  env CTVL_SINDRAS_CPF_TOTAL_PASSWORD="$(rnd)" "$CTVL" apply "$1" --file "$WORK/cfg-mask.yaml" --yes --no-verify >"$WORK/en-apply-$1.out" 2>&1
  if [ -n "${4:-}" ]; then
    post "$1" /groups/ "{\"name\":\"$4\"}"
    post "$1" /permissions/token/groups/ "{\"group\":\"$4\",\"key\":\"SINDRAS_KEY\",\"canPost\":false,\"canGet\":true}"
    "$CTVL" admin "$1" PUT /users/2 --body "{\"username\":\"$MASKED\",\"email\":\"a@example.invalid\",\"groups\":[\"$4\"]}" --yes >/dev/null 2>&1
  fi
}
enable() { # <apelido> <usuario> [args...] (senhas certas do seed)
  local a="$1" u="$2"; shift 2
  env CTVL_SINDRAS_CPF_3_LEFT_2_RIGHT_PASSWORD="$PWU" CTVL_SINDRAS_SVC_TOKENIZE_PASSWORD="$PWS" \
    "$CTVL" enable-detokenize "$a" "$u" --file "$WORK/cfg-mask.yaml" "$@"
}
en_setup s30 cpf_3_left_2_right 2
if [ "$(canget s30 /permissions/token/users/ user "$MASKED")" = "false" ]; then ok "apply (completo) deixou o perfil mascarado com canGet=false"; else bad "10.E: apply escreveu canGet para o mascarado" "$(cat "$WORK/en-apply-s30.out")"; fi
if grep "EXECUTA.*$MASKED@" "$WORK/en-apply-s30.out" | grep -q "'canGet': True"; then bad "o apply imprimiu um corpo com canGet=true para o mascarado"; else ok "nenhum corpo do apply com canGet=true para o mascarado"; fi
expect_rc 0 "enable-detokenize sem --yes (dry-run)" enable s30 "$MASKED"
has "dry-run: nada será escrito" "dry-run declarado"
has "pré-condições \(a\)-\(f\) ok" "dry-run lista as pré-condições verificadas"
has "PUT canGet=true" "dry-run mostra o que escreveria"
if [ "$(canget s30 /permissions/token/users/ user "$MASKED")" = "false" ]; then ok "dry-run não escreveu"; else bad "dry-run escreveu"; fi
expect_rc 3 "(a) usuário que não existe no vault" enable s30 sindras_inexistente
has "\(a\) usuário 'sindras_inexistente' não existe" "mensagem (a)"
expect_rc 3 "(a) usuário que não é perfil mascarado no arquivo" enable s30 sindras_cpf_total
has "\(a\) 'sindras_cpf_total' não é perfil mascarado" "mensagem (a) sem máscara"
expect_rc 3 "(e) senha do usuário ausente do ambiente" env -u CTVL_SINDRAS_CPF_3_LEFT_2_RIGHT_PASSWORD CTVL_SINDRAS_SVC_TOKENIZE_PASSWORD="$PWS" "$CTVL" enable-detokenize s30 "$MASKED" --file "$WORK/cfg-mask.yaml" --yes
has "\(e\) variável CTVL_SINDRAS_CPF_3_LEFT_2_RIGHT_PASSWORD" "mensagem (e): só o NOME da variável"
hasnt "$PWU" "a senha não aparece"
expect_rc 3 "(e) senha do usuário de tokenize ausente" env -u CTVL_SINDRAS_SVC_TOKENIZE_PASSWORD CTVL_SINDRAS_CPF_3_LEFT_2_RIGHT_PASSWORD="$PWU" "$CTVL" enable-detokenize s30 "$MASKED" --file "$WORK/cfg-mask.yaml" --yes
has "\(e\) variável CTVL_SINDRAS_SVC_TOKENIZE_PASSWORD" "mensagem (e) do usuário de tokenize"
sed 's/, perm_user.key: name//' "$WORK/cfg-mask.yaml" >"$WORK/cfg-mask-norefs.yaml"
expect_rc 3 "(f) referência perm_user.key não confirmada" env CTVL_SINDRAS_CPF_3_LEFT_2_RIGHT_PASSWORD="$PWU" CTVL_SINDRAS_SVC_TOKENIZE_PASSWORD="$PWS" "$CTVL" enable-detokenize s30 "$MASKED" --file "$WORK/cfg-mask-norefs.yaml" --yes
has "\(f\)" "mensagem (f)"
if [ "$(canget s30 /permissions/token/users/ user "$MASKED")" = "false" ]; then ok "nenhuma recusa escreveu"; else bad "uma recusa escreveu canGet"; fi
expect_rc 4 "(e) verify-mask falha (senha errada): reverte" env CTVL_SINDRAS_CPF_3_LEFT_2_RIGHT_PASSWORD="$(rnd)" CTVL_SINDRAS_SVC_TOKENIZE_PASSWORD="$PWS" "$CTVL" enable-detokenize s30 "$MASKED" --file "$WORK/cfg-mask.yaml" --yes
has "VERIFY FALHOU.*revertendo canGet=false" "mensagem de rollback"
if [ "$(canget s30 /permissions/token/users/ user "$MASKED")" = "false" ]; then ok "rollback: canGet voltou para false"; else bad "rollback não reverteu"; fi
expect_rc 0 "caminho feliz: máscara correta, verify ok" enable s30 "$MASKED" --yes
has "HABILITADO: $MASKED com canGet=true" "habilitado"
has "$MASKED +cpf_3_left_2_right +OK" "verify-mask do usuário ok"
hasnt "$PWU|$PWS|eyJ" "sem senha nem JWT na saída"
if [ "$(canget s30 /permissions/token/users/ user "$MASKED")" = "true" ]; then ok "vault: canGet=true"; else bad "caminho feliz sem canGet"; fi
OUT="$("$CTVL" plan s30 --file "$WORK/cfg-mask.yaml" 2>&1)"
hasnt "ATUALIZAR +perm.usuário +$MASKED" "o plan seguinte não desfaz o que o enable-detokenize escreveu"
hasnt "HABILITAR DETOKENIZE pendente: rode .ctvl enable-detokenize <ambiente> $MASKED" "e não lista mais a pendência"
OUT="$("$CTVL" apply s30 --file "$WORK/cfg-mask.yaml" --yes --no-verify 2>&1)"
if [ "$(canget s30 /permissions/token/users/ user "$MASKED")" = "true" ]; then ok "apply repetido preserva o canGet habilitado"; else bad "apply desfez o enable"; fi
expect_rc 2 "enable-detokenize não existe offline" "$CTVL" enable-detokenize --offline "$MASKED" --file "$WORK/cfg-mask.yaml"
OUT="$("$CTVL" --help 2>&1)"
has "enable-detokenize <ambiente> <usuario>" "o --help lista o subcomando"
en_setup s31 cpf_aberta 2
expect_rc 3 "(b) máscara atribuída diferente da declarada" enable s31 "$MASKED" --yes
has "\(b\) a máscara atribuída é 'cpf_aberta', diferente da declarada 'cpf_3_left_2_right'" "mensagem (b)"
en_setup s32 cpf_3_left_2_right 1
"$CTVL" admin s32 PUT /masks/1 --body '{"name":"cpf_3_left_2_right","showleft":3,"showright":1,"maskchar":"*"}' --yes >/dev/null 2>&1
expect_rc 3 "(c) máscara do vault com parâmetros diferentes dos declarados" enable s32 "$MASKED" --yes
has "\(c\) a máscara 'cpf_3_left_2_right' no vault difere da declarada em show_right" "mensagem (c)"
mkmask ", status: a_confirmar"
OUT="$(env CTVL_SINDRAS_CPF_3_LEFT_2_RIGHT_PASSWORD="$PWU" CTVL_SINDRAS_SVC_TOKENIZE_PASSWORD="$PWS" "$CTVL" enable-detokenize s30 "$MASKED" --file "$WORK/cfg-m.yaml" --yes 2>&1)"
has "\(c\) a máscara 'cpf_3_left_2_right' está pendente de confirmação" "(c) máscara a confirmar"
en_setup s33 cpf_3_left_2_right 2 g_det
expect_rc 3 "(d) grupo do usuário com canGet=true" enable s33 "$MASKED" --yes
has "\(d\) o grupo 'g_det' do usuário tem canGet=true" "mensagem (d)"
if [ "$(canget s33 /permissions/token/users/ user "$MASKED")" = "false" ]; then ok "(d) nada foi escrito"; else bad "(d) escreveu"; fi

echo
echo "Resultado: $PASS passaram, $FAIL falharam"
[ "$FAIL" -eq 0 ]
