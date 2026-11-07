---
name: vault-factory
description: Abstrai leitura/escrita de secrets em cofres (1Password, Passbolt, pass/gopass, HashiCorp Vault) sem nunca imprimir segredos no chat, no histórico do shell ou em arquivos versionados. A interface principal é o contrato `vault-read <ref>`, que lê o segredo por uma referência com esquema (op://, pass:, gopass:, passbolt:, vault:) sem que a skill consumidora saiba qual cofre está por trás; também provê os padrões de acesso inline e os comandos pb (find/import/export). Os detalhes de cada cofre ficam em providers/<nome>/arquivos.md e providers/<nome>/runbook-linux.md. Use quando o usuário pedir para acessar, ler, atualizar ou transferir secrets entre cofres e arquivos .env, ou quando uma skill precisar de credencial.
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

## Contrato `vault-read` (interface principal)

Skills não conhecem o cofre: guardam a **referência** do segredo (ex.: variável `<SISTEMA>_<SEGREDO>_REF`) e leem com `vault-read <ref>`, que escreve o valor em stdout, sem quebra de linha final, e mais nada.

```bash
curl -H "Authorization: Bearer $(vault-read "$EXEMPLO_API_TOKEN_REF")" "<url>"
```

Esquemas: `op://<cofre>/<item>/<campo>`, `pass:<caminho>`, `gopass:<caminho>`, `passbolt:<id-ou-nome>[#campo]`, `vault:<mount>/<caminho>#<chave>`. Esquema desconhecido: exit 2; CLI ausente: exit 3 (a mensagem aponta o runbook); valor vazio: exit 1. O segredo nunca vai para argv nem para stderr. Contrato completo, códigos de saída e como adicionar um provider: `docs/contrato-provider.md`.

## Providers

Os comandos concretos de cada cofre estão em arquivos separados — **ler o provider antes de executar**:

| Cofre | Esquema | Provider | Runbook (instalação/autenticação) | Uso típico |
|---|---|---|---|---|
| **1Password** | `op://` | `providers/1password/arquivos.md` | `providers/1password/runbook-linux.md` | Credencial AD e tokens; leitura de agente via `op-sa` |
| **Passbolt** (remoto, go-passbolt-cli) | `passbolt:` | `providers/passbolt/arquivos.md` | `providers/passbolt/runbook-linux.md` | Secrets compartilhados; geração de `.env`; `pb find/import/export` |
| **pass / gopass** (local, GPG) | `pass:` / `gopass:` | `providers/pass-gopass/arquivos.md` | `providers/pass-gopass/runbook-linux.md` | Segredos operacionais por caminho (ex.: `redis/<env>/senha`), usados inline |
| **HashiCorp Vault** (remoto, KV v2) | `vault:` | `providers/vault/arquivos.md` | `providers/vault/runbook-linux.md` | Credenciais dos charts (ExternalSecret/ArgoCD); agentes veem só nomes de chaves; escrita com `kv patch` |

Docs desta skill: `docs/contrato-provider.md` (contrato `vault-read`), `docs/autenticacao.md` (Passbolt: setup, MFA, rotação, troubleshooting) e
`docs/importar-chave-gpg-sem-prompt.md` (chave GPG no keyring para pass/gopass sem pinentry) e
`docs/segredo-exposto.md` (segredo em texto claro num arquivo versionado: como achar todas as
ocorrências, no working tree e no histórico, sem imprimir o valor).

## Padrões de acesso inline (independentes do cofre)

O mesmo padrão vale para qualquer cofre — a diferença é só o comando de leitura:

```bash
# pass/gopass: substituição no próprio comando
REDISCLI_AUTH="$(pass show redis/<env>/senha)" redis-cli ping   # REDISCLI_AUTH, não -a: -a expõe a senha em ps

# Passbolt: injeta as secrets no env só do processo filho, nunca no shell interativo
passbolt exec -- bash -c 'dotnet restore'
```

**1Password (`op`):** guarde só a referência (`op://<cofre>/<item>/<campo>`) em variável de ambiente e leia com `vault-read`. Agentes sem o app desktop leem pelo service account com o wrapper `op-sa` (criação e uso em `providers/1password/arquivos.md`).

**HashiCorp Vault:** agentes não leem valores (o login é feito pelo usuário no próprio shell); em sessão de agente só listar nomes de chaves — ver `providers/vault/arquivos.md`.

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

Expor o `pb` e o `vault-read` fora da skill:

```bash
~/.config/ai/skills/vault-factory/scripts/init.sh
source ~/.zshrc   # ou abrir novo terminal
```

## Fluxo típico: gerar .env de um ambiente

1. Identificar o cofre (Passbolt) e o resource id/nome do ambiente (ver provider).
2. `pb import <id-ou-nome> <caminho-do-.env>` — grava sem ecoar.
3. Conferir permissão do arquivo (chmod 600) — o `pb import` já faz.
4. Nunca commitar o `.env`.
