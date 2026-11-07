# Provider: Passbolt (go-passbolt-cli)

Instalação e configuração (Linux/Fedora): ver [runbook-linux.md](runbook-linux.md), fonte canônica.

Detalhes específicos do cofre Passbolt (`https://passbolt.example.com`) usados pela skill
`vault-factory`. Este arquivo é **referência** — a skill aponta para cá.

## Pré-requisitos

- Binário `passbolt` (go-passbolt-cli) no `PATH` — `command -v passbolt`.
- Config em `~/.config/go-passbolt-cli/go-passbolt-cli.toml` com `serveraddress`,
  `userpassword` (passphrase da chave) e `userprivatekey` (chave privada GPG embutida).
- Chave privada exportada em `~/.config/passbolt/passbolt_private.asc`.
- `jq` instalado.
- Servidor acessível: `curl -sS -o /dev/null -w "%{http_code}" https://passbolt.example.com/`
  (esperado `302`).

## Segurança (obrigatório)

- **NUNCA** imprimir no output/chats o conteúdo de `userprivatekey`, `userpassword` ou secrets/notas
  lidas do cofre.
- Ao inspecionar o config, redigir segredos com sed antes de exibir (TOML aceita aspas simples ou
  duplas):
  `sed -E "s/(passphrase|password|key|secret)\s*=\s*['\"].*['\"]/\1=\"***\"/gi" <arquivo>`
- Não versionar o TOML nem os `.env` gerados.
- Preferir os scripts prontos do repositório (`genEnvFromPassbolt.sh`/`updatePassboltFromEnv.sh`)
  a comandos avulsos.

## Verificação rápida de acesso

```bash
passbolt --version
passbolt list users          # só leitura, não expõe secrets
```

Se `list users` retornar a lista, autenticação OK. O primeiro acesso pode pedir MFA TOTP (interativo).

## Instalação

Versão atual: `0.5.1`. Releases em
`https://github.com/passbolt/go-passbolt-cli/releases/download/v0.5.1/`.

### Fedora / RHEL (RPM)

```bash
sudo dnf install -y \
  https://github.com/passbolt/go-passbolt-cli/releases/download/v0.5.1/go-passbolt-cli_0.5.1_linux_amd64.rpm
```

Para arm64, trocar `amd64` por `arm64`.

### Debian / Ubuntu (DEB)

```bash
wget https://github.com/passbolt/go-passbolt-cli/releases/download/v0.5.1/go-passbolt-cli_0.5.1_linux_amd64.deb
sudo apt install -y ./go-passbolt-cli_0.5.1_linux_amd64.deb
```

### Genérico (tar.gz)

```bash
wget https://github.com/passbolt/go-passbolt-cli/releases/download/v0.5.1/go-passbolt-cli_0.5.1_linux_amd64.tar.gz
tar -xzf go-passbolt-cli_0.5.1_linux_amd64.tar.gz
sudo install -m 755 passbolt /usr/local/bin/passbolt
```

## Desinstalação

```bash
sudo rpm -e go-passbolt-cli      # Fedora/RHEL
sudo apt remove go-passbolt-cli  # Debian/Ubuntu
```

⚠️ A desinstalação NÃO remove `~/.config/go-passbolt-cli/` nem `~/.config/passbolt/` — apagar
manualmente apenas se o objetivo for zerar credenciais.

## Configuração de credenciais

- Guia dedicado (fluxo completo, MFA, rotação, troubleshooting): `vault-factory/docs/autenticacao.md`.
- Importar a chave no keyring do GnuPG (para `gopass`/`pass`) sem prompt
  interativo e sem pinentry: `vault-factory/docs/importar-chave-gpg-sem-prompt.md`.

### Opção A — comando `configure`

Fluxo no runbook, seção 4.2 ([runbook-linux.md](runbook-linux.md)): `configure` **sem** `--userPassword`. A passphrase só entra se o CLI a pedir de forma interativa; se não pedir, usar a Opção B. Comportamento a confirmar (runbook, seção 8).

⚠️ Não passar passphrase nem seed TOTP como argumento: aparece no `ps` e no histórico do shell.

### Opção B — editar `~/.config/go-passbolt-cli/go-passbolt-cli.toml`

```toml
serveraddress = 'https://passbolt.example.com'
userpassword = 'SENHA_DA_CHAVE'
userprivatekey = "-----BEGIN PGP PRIVATE KEY BLOCK-----\n...\n-----END PGP PRIVATE KEY BLOCK-----\n"
```

Manter permissão `chmod 600` no arquivo.

## Comandos úteis

```bash
passbolt list resources                          # listar recursos
passbolt get resource --id "<id>" --json         # ver um recurso (JSON, contém secrets — redigir)
passbolt create resource ...                     # criar recurso
passbolt update resource --id "<id>" --description "<texto>"   # atualizar nota
passbolt list users                              # listar usuários
passbolt exec -- <comando>                       # rodar comando com secrets injetados no env
passbolt verify                                  # validar certificado/setup do servidor
```

## CLI `pb` (find / import / export)

Os scripts da skill são acessados pelo comando `pb` (exposto no PATH via `vault-factory/scripts/init.sh`),
que delega para `scripts/pb.sh` → `pb-find.sh`/`pb-import.sh`/`pb-export.sh`. Só `pb` fica symlinkado
em `~/.local/bin`.

Em `import`/`export`, o identificador aceita **UUID ou um trecho do nome** (case-insensitive, via
`scripts/lib.sh:resolve_resource_id`). Se casar mais de um recurso, lista candidatos no erro e pede
para refinar ou usar UUID.

### `pb find <termo>`

Lista `id + nome` dos recursos cujo nome contenha o termo. Só leitura, nunca expõe secret.

```bash
pb find meu-app
# <resource-id>  MeuApp Dev Env
```

### `pb import <id-ou-nome> <output-path>`

Baixa a nota/descrição de um recurso e grava direto num arquivo, sem nunca imprimir o conteúdo no
terminal. Cria o diretório de destino se preciso, pede confirmação antes de sobrescrever, grava com
`chmod 600`.

```bash
pb import <resource-id> ./src/Projeto.Infra.CrossCutting/.env
pb import "meu-app dev" ./src/Projeto.Infra.CrossCutting/.env
```

### `pb export <id-ou-nome> <input-file>`

Caminho inverso: sobrescreve a nota/descrição de um recurso com o conteúdo de um arquivo local. Pede
confirmação antes de sobrescrever e nunca imprime conteúdo no terminal.

### Expor o `pb` fora da skill

```bash
~/.config/ai/skills/vault-factory/scripts/init.sh
source ~/.zshrc   # ou abrir novo terminal
```


## Troubleshooting

- `passbolt: command not found` — binário fora do `PATH`; reinstalar ou usar `/usr/local/bin/passbolt`.
- Erro de autenticação/certificado — conferir `serveraddress` no TOML e conectividade
  (`curl -I https://passbolt.example.com`).
- MFA travando em scripts — o modo não interativo exige `--mfaTotpToken`; o CLI exige a flag, avalie o
  risco (runbook, seção 8). ⚠️ Não passar passphrase nem seed TOTP como argumento: aparece no `ps` e no
  histórico do shell.
- Primeira configuração em máquina nova — exportar a chave privada no navegador Passbolt
  (Configurações → Chave privada) antes de rodar `configure`.

## Referência no contrato (`vault-read`)

Um segredo do Passbolt é referenciado como `passbolt:<id-ou-nome>`, em que `<id-ou-nome>` é o UUID do recurso ou um trecho do nome (case-insensitive, a mesma regra de `pb import` e `pb export`). Exemplo: `passbolt:<id-do-recurso>`.

O valor do segredo nunca é impresso no chat: a referência aponta para o recurso, e a leitura acontece por `vault-read`, sem exibição do conteúdo.
