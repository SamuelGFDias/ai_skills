# Login usuário/senha e renovação de token sem abrir o console

**Confirmado funcionando** na SES-RJ: a conta AD (`AD-SES` no cofre) aceita autenticação direta
por senha nos três clusters (HUB, HML, PRD), sem precisar de MFA/OTP no fluxo de CLI (mesmo a
conta tendo um campo TOTP cadastrado — o desafio de senha do `oc login -u/-p` não o exige, só o
login via navegador talvez exija).

## Pré-requisito: confiar em DUAS CAs por cluster, não só uma

O `oc login -u/-p` fala com **dois** endpoints diferentes, cada um com sua própria CA
autoassinada:

| Endpoint | Host | CA |
|---|---|---|
| API server | `api.ses-rj-<env>.saude.rj.gov.br:6443` | `kube-apiserver-lb-signer` (ver `docs/certificado-tls.md`) |
| Servidor OAuth | `oauth-openshift.apps.ses-rj-<env>.saude.rj.gov.br:443` | `ingress-operator@<timestamp>` |

O login **por token** só toca a API server, por isso só precisa da primeira CA. O login **por
usuário/senha** toca as duas — sem confiar na segunda, falha com
`error: tls: failed to verify certificate: x509: certificate signed by unknown authority`
mesmo já tendo passado `--certificate-authority` para a primeira.

A CA do OAuth é usada pelo Go TLS stack para um host diferente do `--server`, então
`--certificate-authority` do `oc login` não cobre — a forma prática é confiar nela no
**trust store do sistema** (afeta a máquina toda; é uma CA legítima da própria infra SES-RJ,
mesma que o navegador já aceita ao visitar o console):

```bash
# Fedora/RHEL — repetir por ambiente
host="oauth-openshift.apps.ses-rj-<env>.saude.rj.gov.br"
chain=$(mktemp)
echo | openssl s_client -connect "$host:443" -servername "$host" -showcerts 2>/dev/null \
  | awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' > "$chain"
sudo cp "$chain" "/etc/pki/ca-trust/source/anchors/openshift-<env>-ingress-ca.crt"
sudo update-ca-trust
rm -f "$chain"

# confirmar:
echo | openssl s_client -connect "$host:443" -servername "$host" 2>&1 | grep "Verify return code"
# esperado: Verify return code: 0 (ok)
```

Cada cluster (HUB/HML/PRD) tem sua própria CA de ingress — repetir para os três.

## Login direto

```bash
pass show ad-ses/senha | oc login -u "$(pass show ad-ses/usuario)" \
  --server="https://api.ses-rj-<env>.saude.rj.gov.br:6443" \
  --certificate-authority="$HOME/.config/openshift-ca/<env>-ca.crt"
```

A senha vai só por `stdin` (pipe) — `oc login` não tem flag `--password-stdin`, mas se `-p` for
omitida ele lê a senha de stdin quando não há tty interativo. **Nunca** usar `-p "$(pass show
...)"` diretamente — isso expõe a senha como argumento de processo (visível via `ps`).

## Renovar o token guardado no `pass` (sem console)

```bash
for env in hub hml prd; do
  pass show ad-ses/senha | oc login -u "$(pass show ad-ses/usuario)" \
    --server="https://api.ses-rj-$env.saude.rj.gov.br:6443" \
    --certificate-authority="$HOME/.config/openshift-ca/$env-ca.crt" >/dev/null 2>&1
  oc whoami -t | pass insert -e "openshift/$env/token"
done
```

`oc whoami -t | pass insert -e ...` — o token nunca é impresso, vai direto do `oc` para o `pass`
via pipe.

**Não usar `oc logout` entre os ambientes do loop.** `oc logout` revoga o token **no servidor**,
não só localmente (confirmado empiricamente: token de um ambiente salvo no `pass` parou de
funcionar depois que o loop deu `oc logout` antes de passar para o próximo ambiente — só o último
processado, sem `oc logout` depois, sobreviveu). Como cada iteração já mira um `--server`
diferente, não existe cache a "furar" — o `oc login -u/-p` sempre faz uma autenticação de verdade
contra um cluster novo, então o `logout` prévio é desnecessário aqui. Só usar `oc logout` quando o
objetivo for forçar reautenticação no **mesmo** cluster onde já existe um token válido em cache
(nesse caso, sabendo que o token atual daquele cluster será descartado).

## Convenção de nomes no cofre

- `ad-ses/usuario`, `ad-ses/senha` — credencial AD, compartilhada pelos três clusters.
- `openshift/<env>/token` — token de sessão por ambiente, renovável a qualquer momento com o
  bloco acima.

## Cuidado

Login com senha errada repetido pode disparar bloqueio de conta no AD — este fluxo só deve rodar
com a senha correta já confirmada (ex.: vinda do cofre, não digitada manualmente por tentativa).
