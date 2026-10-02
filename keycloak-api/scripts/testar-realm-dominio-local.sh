#!/usr/bin/env bash
# Prova, num Keycloak descartável, que um realm pode responder por um DNS próprio (Frontend URL) na mesma
# instância, com nginx restringindo o host novo ao realm novo. Nada toca em produção.
# Uso: testar-realm-dominio-local.sh [versao-keycloak]   (padrão 26.7.0; requer docker e python3)
set -euo pipefail

KC_VERSION="${1:-26.7.0}"
HOST_A="sso.a.test"      # host "atual" (KC_HOSTNAME da instância)
HOST_B="sso.b.test"      # host novo (Frontend URL do realm novo)
REALM_ANTIGO="condominio"
REALM_NOVO="novo"
NET="kc-fe-test"; KC="kc-fe"; NGX="nginx-fe"
TMP="$(mktemp -d)"; PASS_ADMIN="$(head -c 12 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 14)"
PASS_USER="Senha-teste-1"; falhas=0

limpar() { docker rm -f "$KC" "$NGX" >/dev/null 2>&1 || true; docker network rm "$NET" >/dev/null 2>&1 || true; rm -rf "$TMP"; }
trap limpar EXIT
ok()  { echo "  OK    $*"; }
bad() { echo "  FALHA $*"; falhas=$((falhas+1)); }
C()   { docker run --rm --network "$NET" curlimages/curl -s -m 20 "$@"; }
K()   { docker exec "$KC" /opt/keycloak/bin/kcadm.sh "$@"; }
code(){ C -o /dev/null -w '%{http_code}' "$@"; }
issuer(){ python3 -c "import sys,json;print(json.load(sys.stdin).get('issuer','?'))"; }

docker network create "$NET" >/dev/null
docker run -d --rm --name "$KC" --network "$NET" -e KC_BOOTSTRAP_ADMIN_USERNAME=admin -e KC_BOOTSTRAP_ADMIN_PASSWORD="$PASS_ADMIN" \
  -e KC_HOSTNAME="https://$HOST_A" -e KC_HTTP_ENABLED=true -e KC_PROXY_HEADERS=xforwarded \
  "quay.io/keycloak/keycloak:$KC_VERSION" start-dev >/dev/null

cat > "$TMP/nginx.conf" <<NGINX
events {}
http {
  resolver 127.0.0.11 valid=5s;
  server {   # vhost A: como o de produção (tudo)
    listen 80; server_name $HOST_A;
    location / { set \$u http://$KC:8080; proxy_pass \$u; proxy_set_header Host \$host; proxy_set_header X-Forwarded-Proto https; proxy_set_header X-Forwarded-Host \$host; proxy_set_header X-Forwarded-Port 443; }
  }
  server {   # vhost B: só o realm novo, recursos e robots
    listen 80; server_name $HOST_B;
    location ~ ^/(realms/$REALM_NOVO/|resources/|robots\.txt\$) { set \$u http://$KC:8080; proxy_pass \$u; proxy_set_header Host \$host; proxy_set_header X-Forwarded-Proto https; proxy_set_header X-Forwarded-Host \$host; proxy_set_header X-Forwarded-Port 443; }
    location / { return 404; }
  }
}
NGINX
docker run -d --rm --name "$NGX" --network "$NET" -v "$TMP/nginx.conf:/etc/nginx/nginx.conf:ro" nginx:alpine >/dev/null

echo "aguardando o Keycloak..."
for _ in $(seq 1 60); do docker logs "$KC" 2>&1 | grep -q "Listening on" && break; sleep 3; done
docker logs "$KC" 2>&1 | grep -q "Listening on" || { echo "Keycloak não subiu"; exit 2; }

# Todas as chamadas kcadm num único docker exec (cada kcadm é uma JVM nova: agrupar poupa minutos).
docker exec -e PASS_ADMIN="$PASS_ADMIN" -e PASS_USER="$PASS_USER" -e HOST_B="$HOST_B" -e REALM_ANTIGO="$REALM_ANTIGO" -e REALM_NOVO="$REALM_NOVO" "$KC" bash -c '
set -e
K=/opt/keycloak/bin/kcadm.sh
$K config credentials --server http://localhost:8080 --realm master --user admin --password "$PASS_ADMIN" >/dev/null
for R in "$REALM_ANTIGO" "$REALM_NOVO"; do
  if [ "$R" = "$REALM_NOVO" ]; then $K create realms -s realm="$R" -s enabled=true -s "attributes.frontendUrl=https://$HOST_B" >/dev/null
  else $K create realms -s realm="$R" -s enabled=true >/dev/null; fi
  $K create clients -r "$R" -s clientId="app-$R" -s publicClient=true -s directAccessGrantsEnabled=true -s "redirectUris=[\"https://app.test/*\"]" >/dev/null
  # username >= 3 e nomes >= 2 caracteres: o user profile padrão recusa menos (error-invalid-length)
  $K create users -r "$R" -s username=usuario1 -s enabled=true -s email=usuario1@teste.com -s emailVerified=true -s firstName=Teste -s lastName=Usuario >/dev/null
  $K set-password -r "$R" --username usuario1 --new-password "$PASS_USER" >/dev/null
done'
echo "realms e usuários de teste criados"

echo "== discovery (issuer)"
[ "$(C -H "Host: $HOST_B" "http://$NGX/realms/$REALM_NOVO/.well-known/openid-configuration" | issuer)" = "https://$HOST_B/realms/$REALM_NOVO" ] && ok "realm novo via B anuncia o host B" || bad "realm novo via B"
[ "$(C -H "Host: $HOST_A" "http://$NGX/realms/$REALM_NOVO/.well-known/openid-configuration" | issuer)" = "https://$HOST_B/realms/$REALM_NOVO" ] && ok "realm novo via A também anuncia o host B (o realm é a âncora)" || bad "realm novo via A"
[ "$(C -H "Host: $HOST_A" "http://$NGX/realms/$REALM_ANTIGO/.well-known/openid-configuration" | issuer)" = "https://$HOST_A/realms/$REALM_ANTIGO" ] && ok "realm antigo inalterado no host A" || bad "realm antigo"

echo "== allowlist do host B"
for p in "/realms/$REALM_NOVO/.well-known/openid-configuration" "/realms/$REALM_NOVO/protocol/openid-connect/certs" "/realms/$REALM_NOVO/protocol/openid-connect/logout"; do
  [ "$(code -H "Host: $HOST_B" "http://$NGX$p")" = 200 ] && ok "B $p = 200" || bad "B $p deveria ser 200"
done
for p in /admin/master/console/ /realms/master/.well-known/openid-configuration "/realms/$REALM_ANTIGO/.well-known/openid-configuration" /; do
  [ "$(code -H "Host: $HOST_B" "http://$NGX$p")" = 404 ] && ok "B $p = 404 (bloqueado)" || bad "B $p deveria ser 404"
done

echo "== token e página de login do realm novo"
tok() { C -H "Host: $1" -d client_id="app-$REALM_NOVO" -d grant_type=password -d username=usuario1 -d password="$PASS_USER" -d scope=openid "http://$NGX/realms/$REALM_NOVO/protocol/openid-connect/token" \
  | python3 -c "import sys,json,base64;t=json.load(sys.stdin).get('access_token','');print(json.loads(base64.urlsafe_b64decode(t.split('.')[1]+'=='))['iss'] if t else 'sem-token')"; }
[ "$(tok "$HOST_B")" = "https://$HOST_B/realms/$REALM_NOVO" ] && ok "iss do token via B = host B" || bad "iss via B"
[ "$(tok "$HOST_A")" = "https://$HOST_B/realms/$REALM_NOVO" ] && ok "iss do token via A = host B (o app novo valida um único issuer)" || bad "iss via A"
C -H "Host: $HOST_B" "http://$NGX/realms/$REALM_NOVO/protocol/openid-connect/auth?client_id=app-$REALM_NOVO&redirect_uri=https://app.test/cb&response_type=code&scope=openid" > "$TMP/login.html"
[ "$(grep -c "$HOST_A" "$TMP/login.html" || true)" = 0 ] && ok "HTML de login sem nenhuma referência ao host A" || bad "HTML de login vaza o host A"
grep -q "action=\"https://$HOST_B/realms/$REALM_NOVO/login-actions" "$TMP/login.html" && ok "formulário posta no host B" || bad "action do formulário"

echo; [ "$falhas" = 0 ] && echo "TUDO OK" || { echo "$falhas falha(s)"; exit 1; }
