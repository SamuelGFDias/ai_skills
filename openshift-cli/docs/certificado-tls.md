# Certificado TLS autoassinado nos API servers OpenShift (SES-RJ)

Contexto para quando `oc login` falha com:

```
error: The server uses a certificate signed by unknown authority. You may need to use the
--certificate-authority flag ... or --insecure-skip-tls-verify ...
```

## Por que acontece

O **console web** (porta 443, rota `apps.ses-rj-<env>...`) normalmente usa um certificado que o
navegador já confia. O **API server** (porta 6443, `api.ses-rj-<env>...`) é outra história: por
padrão o OpenShift assina esse certificado com uma CA interna gerada pelo próprio cluster —
`kube-apiserver-lb-signer` — que não está em nenhum trust store público. Isso é esperado e comum,
não é um defeito de rede nem do `oc`.

Confirmar isso inspecionando a cadeia apresentada:

```bash
echo | openssl s_client -connect api.ses-rj-<env>.saude.rj.gov.br:6443 \
  -servername api.ses-rj-<env>.saude.rj.gov.br -showcerts 2>/dev/null \
  | openssl x509 -noout -issuer -subject
```

Se `issuer` aparecer como `OU=openshift, CN=kube-apiserver-lb-signer`, é exatamente esse caso.

## Duas soluções — trade-off

| Opção | Comando | Trade-off |
|---|---|---|
| **Confiar na CA certa (recomendado)** | `oc login --certificate-authority=<arquivo-da-CA> ...` | Escopado, reversível, não mexe no trust store do sistema. Precisa extrair a CA uma vez por cluster. |
| `--insecure-skip-tls-verify` | `oc login --insecure-skip-tls-verify --token=... --server=...` | Mais rápido, mas o `oc` para de validar se está falando com o servidor real — abre superfície para MITM. Evitar como padrão. |

## Extrair e usar a CA (recomendado)

Usar o script `scripts/get-cluster-ca.sh` desta skill:

```bash
~/.config/ai/skills/openshift-cli/scripts/get-cluster-ca.sh api.ses-rj-hml.saude.rj.gov.br
# CA salva em: ~/.config/openshift-ca/api-ca.crt (ou nome equivalente)

oc login --token "$(pass show openshift/hml/token)" \
  --server="https://api.ses-rj-hml.saude.rj.gov.br:6443" \
  --certificate-authority="$HOME/.config/openshift-ca/hml-ca.crt"
```

Repetir por ambiente (`hub`, `hml`, `prd`) — cada cluster gera sua própria CA.

Depois de um login bem-sucedido, o `oc` embute a CA no `~/.kube/config`
(`certificate-authority-data`) daquele contexto — o arquivo `.crt` extraído vira só backup, não é
mais necessário no dia a dia para aquele cluster.

**Isso resolve só o login por token.** Login direto por usuário/senha (`oc login -u/-p`) toca um
segundo host com outra CA (`oauth-openshift.apps...`) — ver `docs/login-usuario-senha.md` para o
passo extra.

## Nota sobre confiança (TOFU)

Extrair a CA direto da conexão TLS ao hostname documentado (`api.ses-rj-<env>.saude.rj.gov.br`) é
"trust on first use" — não é uma verificação independente da CA contra uma fonte publicada
separadamente. Na prática, para clusters internos numa rede/VPN corporativa já confiável, isso é o
padrão de mercado (é o mesmo modelo de confiança do SSH `known_hosts`). Se a organização publicar o
fingerprint da CA por outro canal (documentação assinada, contato direto com o time de
infraestrutura), prefira validar contra essa fonte antes de confiar.
