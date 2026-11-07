# Provider: pass / gopass (cofre local GPG)

Instalação e configuração (Linux/Fedora): ver [runbook-linux.md](runbook-linux.md), fonte canônica.

Detalhes do cofre de senhas local baseado em GPG (`pass` no Linux, `gopass` no Windows), usado por
skills como `nuget-factory`. Este arquivo é **referência** —
a skill `vault-factory` aponta para cá.

## O que é

`pass`/`gopass` guardam segredos em arquivos GPG por caminho (ex.: `openshift/hml/token`). O segredo
é obtido com `pass show <caminho>` e pode ser usado **inline** em comandos, sem nunca aparecer no
histórico do shell nem no chat.

## Pré-requisito (chave GPG)

O `pass`/`gopass` precisa da mesma chave GPG usada pelo Passbolt. Para importá-la no keyring do
GnuPG sem prompt interativo e sem pinentry (usando a passphrase já salva pelo go-passbolt-cli), ver
`vault-factory/docs/importar-chave-gpg-sem-prompt.md`.

## Regra de ouro (segurança)

- **Nunca** imprimir o valor do segredo isolado (`echo`, `cat`, `pass show` sozinho).
- Sempre usar `$(pass show <caminho>)` inline no comando que consome o segredo.
- O token/senha nunca deve ir para o histórico do shell nem para o chat.

## Uso

```bash
pass show openshift/hml/token                          # errado — ecoa o segredo no terminal/contexto
oc login --token="$(pass show openshift/hml/token)" ...  # certo — inline, nunca impresso
```

Inserir/atualizar sem ecoar (via pipe direto do comando que gera):

```bash
oc whoami -t | pass insert -e openshift/hml/token   # o token vai do oc para o pass via pipe
```

## Convenção de nomes usada nos projetos

| Caminho no cofre | Conteúdo |
|---|---|

## passbolt ↔ pass/gopass

- O Passbolt é o cofre "mestre" compartilhado; `pass`/`gopass` são o cofre local derivado para
  tokens operacionais (login automático).
- As duas stacks convivem: a chave é a mesma, e a skill `vault-factory` abstrai a leitura de ambos.

## Referência no contrato (`vault-read`)

O despachante `vault-read` aceita dois esquemas para os segredos deste cofre:

| Esquema | Significado |
|---|---|
| `pass:<caminho>` | Segredo no store do `pass` (`~/.password-store`), caminho `<serviço>/<ambiente>/<nome>` |
| `gopass:<caminho>` | Segredo no store do `gopass`, mesmo padrão de caminho |
