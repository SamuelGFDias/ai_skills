# Realm para uma aplicação nova, com DNS próprio na mesma instância

Conhecimento provado num Keycloak 26.7.0 local descartável (script `scripts/testar-realm-dominio-local.sh`).
Produção nunca foi tocada pela prova.

## Quando usar
Uma aplicação nova precisa de SSO em um realm próprio e o usuário dela **não deve ver** o hostname do Keycloak
atual (ex.: `sso.samueldias.dev.br`): ela passa a ver `sso.<dominio-novo>`.

## O que é verdade (provado) e o que NÃO é
- O Keycloak **não escolhe o realm pelo Host**. O realm vem do caminho (`/realms/<nome>/...`). Pedir a configuração
  de um realm com outro `Host`/`X-Forwarded-Host` devolve o `issuer` do hostname fixo da instância.
- O hostname da instância é um só (`KC_HOSTNAME`, hostname v2). Para o realm novo anunciar outro DNS, use o campo
  **Frontend URL do realm** (Realm settings > General; atributo `frontendUrl`): ele sobrescreve issuer e endpoints
  **só daquele realm**. Os outros realms não mudam.
- O realm com Frontend URL anuncia sempre o host novo, mesmo se acessado pelo host antigo: um realm = um endereço
  público. Para a aplicação que valida o `iss` isso significa **um único issuer**. Por isso NÃO reaproveite um realm
  em uso trocando a Frontend URL: o `iss` dos tokens muda e a aplicação antiga passa a recusá-los.
- O nginx **não é dispensável**: o DNS novo precisa de vhost próprio, certificado TLS e registro A.
- `keycloak.conf` e `KC_HOSTNAME` não mudam, e o Keycloak não reinicia.
- `.cpp` (e outras extensões inventadas) não é domínio de topo: use um domínio real.
- Armadilha de teste: o user profile padrão recusa username com menos de 3 e nomes com menos de 2 caracteres
  (`error-invalid-length`).

## Caminhos
| | O que é | Quando |
|---|---|---|
| **A. Realm novo + Frontend URL** (recomendado) | mesma instância, realm novo, host novo | a pessoa só não deve ver o seu domínio/realm |
| **B. Segunda instância** (container + banco novos) | isolamento total de admin, dados, tema, SMTP | app de outro cliente/pessoa; custa ~1 GB de memória e mais um banco |
| **C. Hostname dinâmico** (`hostname-strict=false`) | URLs seguem o host da requisição | **desaconselhado**: o issuer varia por host e quebra a validação do backend |

## Checklist do caminho A (ordem importa)
1. DNS: registro A de `sso.<novo>` para o IP do servidor.
2. Certificado Let's Encrypt de `sso.<novo>` (o nginx do host usa `/etc/letsencrypt/live/<host>/`).
3. Keycloak: criar o realm e preencher a **Frontend URL** `https://sso.<novo>` **antes** de abrir o vhost ao público.
4. Client da aplicação (público + PKCE S256, `Valid Redirect URIs` e `Web Origins` exatos do app novo).
5. Google IdP (se houver): autorizar no Google Cloud o redirect
   `https://sso.<novo>/realms/<realm>/broker/google/endpoint` (o redirect é por host **e** realm).
6. Tema de login: é por realm (`loginTheme`); copiar o tema para a pasta de temas montada no container.
7. nginx: vhost abaixo (allowlist).
8. Aplicação: `Keycloak__Authority=https://sso.<novo>/realms/<realm>` e a origem do Keycloak na CSP do frontend.
9. Validar: `curl https://sso.<novo>/realms/<realm>/.well-known/openid-configuration` (issuer com o host novo),
   `/admin/` e `/realms/master/` no host novo dão 404, login completo no navegador.

## vhost do nginx do host novo (provado)
```nginx
server {
    listen 80;
    server_name sso.NOVO.com.br;
    return 301 https://$host$request_uri;
}
server {
    listen 443 ssl;
    server_name sso.NOVO.com.br;
    ssl_certificate     /etc/letsencrypt/live/sso.NOVO.com.br/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/sso.NOVO.com.br/privkey.pem;
    resolver 127.0.0.11 valid=10s;

    # só o realm novo, os recursos do tema e o robots; o resto é 404 (bloqueia /admin, master e os outros realms)
    location ~ ^/(realms/REALM_NOVO/|resources/|robots\.txt$) {
        set $upstream_app http://keycloak:8080;
        proxy_pass $upstream_app;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
    }
    location / { return 404; }
}
```
Sem a allowlist o mesmo processo responderia o console de administração e os outros realms pelo domínio novo.

## Prova local (antes de tocar na produção)
`scripts/testar-realm-dominio-local.sh [versao]` sobe um Keycloak descartável (`start-dev`, `KC_HOSTNAME` fixo,
`KC_PROXY_HEADERS=xforwarded`) e um nginx com dois hosts, cria dois realms (um com Frontend URL) e confere: issuer do
realm novo e do antigo, allowlist do host novo (200 no realm novo, 404 em admin/master/outro realm), `iss` do token e
HTML de login sem nenhuma referência ao host antigo. Termina com `TUDO OK` e limpa containers e rede sozinho.
Requer docker e python3; leva alguns minutos (a JVM do Keycloak e cada `kcadm` são lentos).

## Riscos e rollback
- Um realm com Frontend URL deixa de anunciar o host antigo: nunca aplicar em realm em produção sem trocar a aplicação.
- Rollback: apagar o atributo `frontendUrl` do realm e remover o vhost novo; o realm volta ao hostname da instância.
- Ações em produção (Keycloak, nginx global, DNS, certificado, Google Cloud) são manuais do usuário.
- Sessões e cookies são por host: o login no host novo não aproveita sessão do antigo.

## Lacuna conhecida da skill
Criar realm, definir `frontendUrl`/`loginTheme`, criar client e IdP ainda não têm subcomando `kc`. Candidato:
`kc set-realm-attr` com dry-run por padrão, como `kc set-client-attr`. Enquanto isso, as chamadas REST estão no repo
`condominio_app` em `keycloak/aplicar-tema-login.sh` (idempotente, dry-run por padrão, `--aplicar`, `--desfazer`).
