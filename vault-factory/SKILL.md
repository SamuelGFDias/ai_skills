---
name: vault-factory
description: Abstrai leitura/escrita de secrets em cofres (Passbolt, pass/gopass) sem nunca imprimir segredos no chat, no histórico do shell ou em arquivos versionados. Provê os padrões de acesso inline e os comandos pb (find/import/export). Os detalhes de cada cofre ficam em providers/ — Passbolt em providers/passbolt/arquivos.md, pass/gopass em providers/pass-gopass/arquivos.md. Use quando o usuário pedir para acessar, ler, atualizar ou transferir secrets entre cofres e arquivos .env.
---

# Skill: vault-factory

**Tipo:** internal

## Quando executar

- Pedidos para ler, criar, atualizar ou exportar secrets (senhas, tokens, chaves, `.env`) de um cofre.
- Gerar `.env` de ambientes a partir de um cofre.
- Importar/exportar notas entre o cofre e arquivos locais sem expor conteúdo.
- Qualquer skill que precise de credencial sem vazar no histórico (as demais skills apontam para cá).

## Princípio de segurança (regra de ouro)

- **NUNCA** imprimir segredo (conteúdo de secret/nota, `userprivatekey`, `userpassword`, token) no
  output do chat, no histórico do shell, em logs ou em arquivos versionados.
- Ler secrets sempre **inline** no comando que consome (`$(pass show ...)` / `passbolt exec -- ...`),
  nunca `echo`/`cat`/`pass show` isolado.
- Ao inspecionar config com segredos, redigir antes de exibir:
  `sed -E "s/(passphrase|password|key|secret)\s*=\s*['\"].*['\"]/\1=\"***\"/gi" <arquivo>`
- Nunca versionar `.env` gerados nem arquivos de config com segredo.
- Quando o repositório tiver scripts prontos (ex.: `genEnvFromPassbolt.sh`/`updatePassboltFromEnv.sh`),
  preferi-los a comandos avulsos.
- Se o usuário colar um secret no chat por engano, avisar que ele ficou no histórico e que o ideal é
  rotacionar.

## Providers

Os comandos concretos de cada cofre estão em arquivos separados — **ler o provider antes de executar**:

| Cofre | Onde | Uso típico |
|---|---|---|
| **Passbolt** (remoto, go-passbolt-cli) | `providers/passbolt/arquivos.md` | Secrets compartilhados; geração de `.env`; `pb find/import/export` |
| **pass / gopass** (local, GPG) | `providers/pass-gopass/arquivos.md` | Tokens operacionais por caminho (ex.: `openshift/hml/token`), usados inline |

Docs desta skill: `docs/autenticacao.md` (Passbolt: setup, MFA, rotação, troubleshooting) e
`docs/importar-chave-gpg-sem-prompt.md` (chave GPG no keyring para pass/gopass sem pinentry).

## Padrões de acesso inline (independentes do cofre)

O mesmo padrão vale para qualquer cofre — a diferença é só o comando de leitura:

```bash
# pass/gopass: substituição no próprio comando
oc login --token="$(pass show openshift/hml/token)" ...

# Passbolt: injeta as secrets no env só do processo filho, nunca no shell interativo
passbolt exec -- bash -c 'dotnet restore'
```

## Comandos `pb` (find / import / export)

A skill expõe o CLI único `pb` (via `scripts/init.sh` → symlink em `~/.local/bin`), que delega para
`pb-find.sh` / `pb-import.sh` / `pb-export.sh` — mesmo padrão de CLI único usado em `keycloak-api`
(`kc`) e `nuget-factory` (`nexus`).

- `pb find <termo>` — lista `id + nome` dos recursos cujo nome contenha o termo (só leitura, sem secret).
- `pb import <id-ou-nome> <output-path>` — baixa a nota de um recurso e grava num arquivo (chmod 600),
  sem ecoar conteúdo. Identificador aceita UUID ou trecho do nome.
- `pb export <id-ou-nome> <input-file>` — sobrescreve a nota do recurso com o conteúdo de um arquivo
  local, com confirmação, sem ecoar.

Detalhes completos e exemplos: `providers/passbolt/arquivos.md`.

Expor o `pb` fora da skill:

```bash
~/.config/ai/skills/vault-factory/scripts/init.sh
source ~/.zshrc   # ou abrir novo terminal
```

## Fluxo típico: gerar .env de um ambiente

1. Identificar o cofre (Passbolt) e o resource id/nome do ambiente (ver provider).
2. `pb import <id-ou-nome> <caminho-do-.env>` — grava sem ecoar.
3. Conferir permissão do arquivo (chmod 600) — o `pb import` já faz.
4. Nunca commitar o `.env`.
