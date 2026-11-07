# Configuração de autenticação — passbolt-cli

Guia focado em como o `passbolt` (go-passbolt-cli) autentica no cofre Passbolt da SES-RJ
(`https://passbolt.saude.rj.gov.br`). Para instalação do binário, ver `SKILL.md` na raiz desta
skill.

## O que o CLI precisa

Três informações, todas guardadas em `~/.config/go-passbolt-cli/go-passbolt-cli.toml`:

- `serveraddress` — URL do servidor Passbolt.
- `userprivatekey` — chave privada GPG do usuário (embutida no TOML ou referenciada por arquivo).
- `userpassword` — passphrase que destrava essa chave privada.

A chave privada em si normalmente fica exportada em `~/.config/passbolt/passbolt_private.asc`.

## Pré-requisito: exportar a chave privada

Antes de configurar, exporte a chave privada pela interface web do Passbolt:
**Configurações → Chave privada → Exportar**. Salve o arquivo `.asc` (ex: em
`~/.config/passbolt/passbolt_private.asc`, `chmod 600`).

## Opção A — comando `configure`

Fluxo no runbook, seção 4.2 (`../../providers/passbolt/runbook-linux.md`): `configure` **sem** `--userPassword`. A passphrase só entra se o CLI a pedir de forma interativa; se não pedir, usar a Opção B. O comportamento ainda precisa ser confirmado (runbook, seção 8).

⚠️ Não passar passphrase nem seed TOTP como argumento: aparece no `ps` e no histórico do shell.

## Opção B — editar o TOML diretamente

Arquivo: `~/.config/go-passbolt-cli/go-passbolt-cli.toml`.

```toml
serveraddress = 'https://passbolt.saude.rj.gov.br'
userpassword = "<SENHA>"
userprivatekey = "-----BEGIN PGP PRIVATE KEY BLOCK-----\n...\n-----END PGP PRIVATE KEY BLOCK-----\n"
```

- `userprivatekey` fica **embutida** (com `\n` no lugar das quebras de linha). É o estado ideal: os
  scripts `pb` chamam o CLI sem `--userPrivateKeyFile`, então a chave precisa estar no TOML. Omiti-la
  exige a flag em todo comando, o que não é o fluxo padrão (ver `../../providers/passbolt/runbook-linux.md`,
  seções 4.1 e 8).
- `chmod 600 ~/.config/go-passbolt-cli/go-passbolt-cli.toml` — o arquivo guarda segredos em texto
  puro.

## Verificar que a autenticação funcionou

```bash
passbolt --version
passbolt list users     # só leitura, não expõe secrets
```

Se `list users` retornar a lista, autenticação OK. O primeiro acesso pode pedir MFA TOTP
(interativo, modo padrão `interactive-totp`).

## MFA em scripts/automação

O modo não-interativo (`--mfaMode noninteractive-totp`) exige a flag `--mfaTotpToken`, que recebe a seed em argv. O CLI exige a flag; avalie o risco (ver `../../providers/passbolt/runbook-linux.md`, seção 8, Pendências).

⚠️ Não passar passphrase nem seed TOTP como argumento: aparece no `ps` e no histórico do shell.

Para uso manual, deixar o modo padrão (`interactive-totp`) já resolve.

## Trocar/rotacionar credenciais

Repetir a Opção A ou B com a nova passphrase/chave sobrescreve a configuração anterior — não é
necessário desinstalar o CLI. Rotacionar é obrigatório sempre que a passphrase ou a chave privada
tiver sido exposta (ex: colada em texto puro num chat, log ou terminal compartilhado).

## Troubleshooting

- **`passbolt: command not found`** — binário fora do `PATH`; ver instalação em `SKILL.md`.
- **Erro de autenticação/certificado** — conferir `serveraddress` no TOML e conectividade:
  `curl -sS -o /dev/null -w "%{http_code}" https://passbolt.saude.rj.gov.br/` (esperado `302`).
- **MFA travando em script** — o modo não interativo exige `--mfaTotpToken`; o CLI exige a flag, avalie o risco (ver `../../providers/passbolt/runbook-linux.md`, seção 8). ⚠️ Não passar passphrase nem seed TOTP como argumento: aparece no `ps` e no histórico do shell.
- **Máquina nova, nenhuma credencial ainda** — exportar a chave privada pelo navegador Passbolt
  antes de rodar `configure`.

## Segurança

- Nunca imprimir `userprivatekey` ou `userpassword` em terminal compartilhado, chat ou log.
- Ao inspecionar o TOML para debug, redigir segredos antes de exibir. O CLI aceita aspas simples
  **ou** duplas nos valores — um `sed` de redação precisa cobrir os dois casos:
  ```bash
  sed -E "s/(passphrase|password|key|secret)\s*=\s*['\"].*['\"]/\1=\"***\"/gi" <arquivo>
  ```
