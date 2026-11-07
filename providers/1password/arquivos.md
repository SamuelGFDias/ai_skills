# Provider: 1Password (`op`)

Instalação e configuração (Linux/Fedora): ver [runbook-linux.md](runbook-linux.md), fonte canônica.

Referência de como o cofre 1Password é usado pelas skills. Este arquivo é **referência** — a skill `vault-factory` aponta para cá. Os caminhos abaixo são exemplos de setup de uma máquina; cada usuário ajusta os seus.

## O que é

O CLI `op` lê segredos por referência `op://<cofre>/<item>/<campo>`. A leitura é feita inline (`op read`), nunca impressa no chat nem gravada em arquivo versionado.

## Setup (por máquina)

- CLI `op` instalado.
- Service account com token guardado fora do repositório (`~/.config/op/service-account-token`, modo 600). O token não é exportado pelo shell: só o `op-sa` o lê, e só para cada chamada. A service account precisa de acesso ao cofre usado.
- Referências dos segredos em variáveis `<SISTEMA>_<SEGREDO>_REF`, por exemplo em `~/.config/ai/refs.env` (modo 600):
  - `EXEMPLO_API_TOKEN_REF="op://<cofre>/<item>/<campo>"`

## Uso

```bash
vault-read "$EXEMPLO_API_TOKEN_REF"                # ok: lê para uso inline
senha=$(vault-read "$EXEMPLO_API_TOKEN_REF")       # ok: nunca ecoar
```

Senha nunca como argumento de processo (`-p "$(op read ...)"`): fica visível em `ps`. Passar por stdin.

## `op-sa`: `op` com o service account, sem depender do ambiente

O `OP_SERVICE_ACCOUNT_TOKEN` costuma **não** estar no ambiente de um agente: o `~/.zshenv` só é lido pelo zsh,
e o shell do agente é bash. Sem o token, o `op` cai no login interativo e falha com
`authorization prompt dismissed`. Em vez de exportar o token em todo processo, use um wrapper que o carrega
do arquivo só para a chamada.

O wrapper é `vault-factory/scripts/op-sa`, no repo. Crie o symlink `~/.local/bin/op-sa` apontando para ele
(ver `runbook-linux.md`, seção 4.1). O script lê o token de `OP_SA_TOKEN_FILE` (padrão
`~/.config/op/service-account-token`) e o passa só para a chamada do `op`. Não copiar o script para outro
lugar: o symlink mantém uma versão só.

Pré-requisitos: o token em `~/.config/op/service-account-token` (permissão `600`) e `~/.local/bin` no `PATH`.

Testar sem imprimir o valor:

```bash
op-sa read "$EXEMPLO_API_TOKEN_REF" >/dev/null && echo OK
```

Regras de uso:

- Trocar `op` por `op-sa` em qualquer script ou comando de agente. A senha continua indo por variável ou stdin, nunca por argumento.
- Em shell de agente (bash), as variáveis `*_REF` também podem faltar: `set -a; . ~/.config/ai/refs.env; set +a`.
- Falha `authorization prompt dismissed` = o `op` não achou o token: usar `op-sa`.

## Referência no contrato (`vault-read`)

No contrato do `vault-factory`, o 1Password é o esquema `op://<cofre>/<item>/<campo>`: `vault-read op://<cofre>/<item>/<campo>` escreve o valor em stdout, sem quebra de linha final. O `vault-read` usa `op-sa` quando ele existe no PATH (service account, sem prompt) e cai para `op` caso contrário. CLI ausente: exit 3, apontando `providers/1password/runbook-linux.md`. Contrato completo em `vault-factory/docs/contrato-provider.md`.
