# Contrato de provider de segredo (`vault-read`)

Toda skill que precisa de um segredo lê por uma **referência com esquema** e não sabe qual cofre está por trás. O despachante `vault-read` (`vault-factory/scripts/vault-read.sh`) traduz a referência para o provider certo.

```bash
vault-read <ref>    # valor em stdout, sem quebra de linha final, e mais nada
```

## Esquemas

| Esquema | Exemplo | Provider | Leitura | Runbook |
|---|---|---|---|---|
| `op://` | `op://<cofre>/<item>/<campo>` | 1Password | O estado do arquivo de token (`OP_SA_TOKEN_FILE`, padrão `~/.config/op/service-account-token`) é avaliado **sempre**, esteja ou não o `op-sa` no PATH. Existente porém vazio (ou só `\r\n`, ou diretório) é erro (exit 1), nunca fallback para a sessão pessoal. Legível e não vazio: `op-sa read`, localizado no PATH ou, senão, como irmão do próprio `vault-read` (resolvendo symlinks). Inexistente/ilegível: `op read` direto (app desktop). O `op-sa` também recusa token vazio. A referência exige `<cofre>/<item>/<campo>` (item inteiro: exit 2) | `providers/1password/runbook-linux.md` |
| `pass:` | `pass:<caminho>` | pass | `pass show <caminho>`, só a 1ª linha; o alvo tem de ser arquivo do store (`${PASSWORD_STORE_DIR:-~/.password-store}/<caminho>.gpg`), diretório ou entrada inexistente: exit 1 | `providers/pass-gopass/runbook-linux.md` |
| `gopass:` | `gopass:<caminho>` | gopass | `gopass show -o <caminho>` | `providers/pass-gopass/runbook-linux.md` |
| `passbolt:` | `passbolt:<id-ou-nome>[#campo]` (sinônimo exato: `passbolt://<id-ou-nome>[#campo]`) | Passbolt | `passbolt get resource`; `campo` ∈ `password` (padrão, sem `#`), `description` (a nota), `username`, `uri`; campo fora da lista: exit 2 (resolução de nome em `scripts/lib.sh`) | `providers/passbolt/runbook-linux.md` |
| `vault:` | `vault:<mount>/<caminho>#<chave>` | HashiCorp Vault (KV v2) | `vault kv get -mount=<mount> -field=<chave> <caminho>` | `providers/vault/runbook-linux.md` |

## Invariantes

1. O segredo nunca vai para argv de processo (do script ou de filho) e nunca é impresso em stderr nem em mensagem de erro. Erros dizem o esquema e o motivo, nunca o valor nem o caminho do segredo. O stderr dos CLIs é descartado.
2. Valor vazio é falha (exit != 0). Verificação que aceita entrada vazia passa em falso; ver a skill `bash-scripting-pitfalls`.
3. Esquema desconhecido ou ausente: exit 2 com mensagem de uso. O despachante não adivinha o provider.
4. CLI do provider ausente: exit 3, e a mensagem aponta para `providers/<nome>/runbook-linux.md`.
5. Sem `eval`, sem expansão da referência como código, aspas em tudo, `set -euo pipefail`.
6. Referência cujo id, caminho, mount ou chave começa com `-` é rejeitada com exit 2 ("referência inválida"), antes de qualquer CLI ser chamado, para não ser lida como flag. Onde o CLI aceita `--` antes do caminho (`pass`, `vault`), ele também é passado.

## Códigos de saída

| Código | Significado |
|---|---|
| 0 | Segredo escrito em stdout |
| 1 | Falha de leitura no provider (sessão, permissão, recurso inexistente) ou valor vazio |
| 2 | Esquema ausente, desconhecido ou referência malformada |
| 3 | CLI do provider ausente no PATH |

## Como adicionar um provider novo

1. Escolha um esquema que não colida com os existentes (`<nome>:` ou `<nome>://`).
2. Em `vault-factory/scripts/vault-read.sh`, crie `read_<nome>()` seguindo as invariantes (`require_cli`, `emit`, `2>/dev/null` nos CLIs) e adicione o `case` em `main`.
3. Escreva `providers/<nome>/runbook-linux.md` (instalação e autenticação, com placeholders `<...>`) e `providers/<nome>/arquivos.md`.
4. Acrescente a linha na tabela de providers do `vault-factory/SKILL.md` e, no `arquivos.md` do provider, uma seção "Referência no contrato (`vault-read`)" com o esquema.
5. Cubra o novo esquema em `vault-factory/tests/test-vault-read.sh` (despacho, sem newline final, valor vazio, CLI ausente, segredo fora de argv/stderr).

## Como a skill consumidora referencia um segredo

A skill guarda a **referência** em variável de ambiente, nunca o provider nem o valor, e lê na hora do uso:

```bash
# ~/.zshenv (ou equivalente); só a referência, nunca o valor
export EXEMPLO_API_TOKEN_REF='op://<cofre>/<item>/<campo>'

# na skill: o cofre atrás da referência é indiferente
curl -H "Authorization: Bearer $(vault-read "$EXEMPLO_API_TOKEN_REF")" "<url>"
```

Trocar de cofre é trocar o valor da variável (`pass:<caminho>`, `vault:<mount>/<caminho>#<chave>`, ...), sem alterar a skill. Nome da variável: `<SISTEMA>_<SEGREDO>_REF`.

## Limites do contrato

- O contrato cobre só **leitura**. Escrita continua específica de cada provider (ex.: `pb export` no Passbolt, `kv patch` no Vault): ver o `arquivos.md` do provider.
- O `vault-read` descarta o stderr dos CLIs de propósito (não vazar segredo): erro de autenticação do provider aparece como "falha ao ler"; para diagnosticar, rodar o CLI do provider direto.
- Integrações de terceiros que têm plugin próprio de cofre ficam fora (ex.: `GLAB_USE_OP_PLUGIN` do `glab`).
- `vault kv get -field` de uma chave que guarda valor não escalar pode sair em formato Go `map[...]`, que a checagem de JSON do `vault-read` não reconhece; nesse caso o texto é emitido como se fosse o segredo.
- O filtro de placeholder do validador não distingue `<segredo>` entre aspas de um placeholder legítimo.
