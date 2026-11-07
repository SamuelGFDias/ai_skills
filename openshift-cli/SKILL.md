---
name: openshift-cli
description: Instala o OpenShift CLI (oc/kubectl) e autentica nos clusters SES-RJ (HUB, HML, PRD) — login por token, tratamento de CA autoassinada dos API servers, e gestão de contextos. Use quando o usuário pedir para instalar/configurar o oc, logar num cluster OpenShift da SES-RJ, trocar de ambiente/projeto, ou resolver erro de certificado no oc login.
---

# Skill: openshift-cli

**Tipo:** internal

## Quando executar

Pedidos para instalar o `oc`/`kubectl`, autenticar num cluster OpenShift SES-RJ (HUB/HML/PRD),
trocar de contexto/projeto, ou resolver `error: The server uses a certificate signed by unknown
authority` no `oc login`.

## Pré-requisitos

- Cofre de senhas configurado (`pass` no Linux, `gopass` no Windows) — ver skill `vault-factory`
  para a chave GPG. Runbook completo: `Runbook — Gopass e Pass` na wiki.
- Fonte oficial: `wiki.saude.rj.gov.br/en/plataforma/openshift/runbooks/instalacao-openshift-cli`.

## Instalação (Linux)

```bash
curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz
curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/sha256sum.txt
grep openshift-client-linux.tar.gz sha256sum.txt | sha256sum -c -   # deve dar SUCESSO
tar -xzf openshift-client-linux.tar.gz
sudo install -m 0755 oc kubectl /usr/local/bin/
oc version --client && kubectl version --client
```

Para arm64, usar o arquivo com sufixo `-arm64` disponível no mesmo mirror. A versão do PRD é
OCP 4.15.x — se houver erro de incompatibilidade, baixar a versão exata pelo próprio console do
cluster (Help → Command Line Tools) em vez do mirror genérico.

## Ambientes (clusters SES-RJ)

| Ambiente | Console (Web) | API Server |
|---|---|---|
| HUB | `console-openshift-console.apps.ses-rj-hub.saude.rj.gov.br` | `api.ses-rj-hub.saude.rj.gov.br:6443` |
| HML | `console-openshift-console.apps.ses-rj-hml.saude.rj.gov.br` | `api.ses-rj-hml.saude.rj.gov.br:6443` |
| PRD | `console-openshift-console.apps.ses-rj-prd.saude.rj.gov.br` | `api.ses-rj-prd.saude.rj.gov.br:6443` |

## Login por token (fluxo padrão)

1. No console do ambiente, avatar (canto superior direito) → **Copy login command** → copia o
   valor após `--token=`.
2. Guardar no cofre (nunca digitar o token em texto puro no chat/histórico):
   ```bash
   pass insert openshift/<env>/token      # <env> = hub | hml | prd
   ```
3. Login:
   ```bash
   oc login --token="$(pass show openshift/<env>/token)" \
     --server="https://api.ses-rj-<env>.saude.rj.gov.br:6443"
   ```

Se der `error: The server uses a certificate signed by unknown authority`, ver
`docs/certificado-tls.md` — **não** usar `--insecure-skip-tls-verify` como primeira opção.

Renovar sem abrir o console: confirmado que a conta AD (`ad-ses/usuario` e `ad-ses/senha` no
cofre) loga direto via `oc login -u/-p` nos três clusters, sem MFA — mas exige confiar numa
**segunda CA** (a do servidor OAuth, diferente da CA da API). Fluxo completo:
`docs/login-usuario-senha.md`.

## Gerenciar contextos

```bash
oc config get-contexts              # lista os clusters/projetos já autenticados
oc config use-context <nome>        # troca sem precisar logar de novo
oc project <projeto>                # troca só o namespace no contexto atual
oc whoami --show-server             # confirma em qual cluster está agora
```

Depois do primeiro `oc login --certificate-authority=...` bem-sucedido, a CA fica embutida no
`~/.kube/config` — não é preciso repetir a flag nos logins seguintes ao mesmo cluster.

## Segurança (obrigatório)

- Nunca imprimir token/senha no terminal, chat ou log. Usar sempre `$(pass show ...)` inline no
  comando, nunca `echo`/`cat` do segredo isolado.
- Não usar `--insecure-skip-tls-verify` sem antes tentar `docs/certificado-tls.md`.
- Cuidado com `oc login -u/-p` repetido com senha errada — pode disparar bloqueio de conta no
  provedor de identidade.

## Referências

- `docs/certificado-tls.md` — por que a API usa CA autoassinada e como confiar nela corretamente.
- `docs/login-usuario-senha.md` — login direto usuário/senha e renovação de token sem console.
- `scripts/get-cluster-ca.sh` — extrai a CA raiz de um cluster para uso com `--certificate-authority`.
- Skill `redis-port-forward` — usa este `oc` já autenticado para abrir túnel até o Redis.
- Skill `vault-factory` — chave GPG usada pelo `pass`/`gopass` que guarda os tokens.
