---
name: passbolt-cli
description: Instala, configura e usa o go-passbolt-cli (binario `passbolt`) para ler/atualizar secrets no cofre Passbolt (https://passbolt.example.com). Inclui o fluxo de instalação validado (RPM/DEB/tar.gz), configuração de credenciais GPG, comandos de consulta e os scripts do repositório MeuApp (genEnvFromPassbolt.sh e updatePassboltFromEnv.sh). Use quando o usuário pedir para acessar, instalar, desinstalar ou manipular secrets do Passbolt.
---

# Skill: passbolt-cli

## Quando executar

Quando houver pedidos para acessar a API do Passbolt, instalar/desinstalar/reinstalar o Passbolt
CLI, ler ou atualizar secrets no cofre, ou gerar `.env` de ambientes a partir do Passbolt.

## Pré-requisitos

- Binário `passbolt` (go-passbolt-cli) instalado no `PATH` — `command -v passbolt`.
- Config em `~/.config/go-passbolt-cli/go-passbolt-cli.toml` com `serveraddress`,
  `userpassword` (passphrase da chave) e `userprivatekey` (chave privada GPG embutida).
- Chave privada exportada em `~/.config/passbolt/passbolt_private.asc`.
- `jq` instalado (necessário para os scripts do repositório).
- Servidor acessível: `curl -sS -o /dev/null -w "%{http_code}" https://passbolt.example.com/`
  (esperado `302`).

## Segurança (obrigatório)

- **NUNCA** imprimir no output/chats o conteúdo de `userprivatekey`, `userpassword` ou o conteúdo
  de secrets/notas lidas do cofre.
- Ao inspecionar o config, redigir segredos com sed antes de exibir. O TOML aceita aspas simples ou
  duplas, então o regex precisa cobrir os dois casos:
  `sed -E "s/(passphrase|password|key|secret)\s*=\s*['\"].*['\"]/\1=\"***\"/gi" <arquivo>`.
- Não versionar o TOML nem os `.env` gerados.
- Quando o repositório tiver scripts prontos (`genEnvFromPassbolt.sh` / `updatePassboltFromEnv.sh`),
  preferi-los a comandos avulsos.

## Verificação rápida de acesso

```bash
passbolt --version
passbolt list users          # só leitura, não expõe secrets
```

Se `list users` retornar a lista, autenticação OK. O primeiro acesso pode pedir MFA TOTP
(interativo).

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

Guia dedicado (fluxo completo, MFA, rotação, troubleshooting): `docs/autenticacao.md` nesta skill.

### Opção A — comando `configure`

```bash
passbolt configure \
  --serverAddress https://passbolt.example.com \
  --userPrivateKeyFile ~/.config/passbolt/passbolt_private.asc \
  --userPassword 'SENHA_DA_CHAVE'
```

### Opção B — editar `~/.config/go-passbolt-cli/go-passbolt-cli.toml`

```toml
serveraddress = 'https://passbolt.example.com'
userpassword = 'SENHA_DA_CHAVE'
userprivatekey = "-----BEGIN PGP PRIVATE KEY BLOCK-----\n...\n-----END PGP PRIVATE KEY BLOCK-----\n"
```

A chave pode ser embutida em `userprivatekey` (com `\n` escapado) ou referenciada por arquivo via
flag global `--userPrivateKeyFile` (não salva no TOML). Manter permissão `chmod 600` no arquivo.

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

## CLI único `pb` (find / import / export)

Os scripts da skill são acessados por um único comando exposto no PATH, `pb`, que delega para o
script interno correspondente (`scripts/pb.sh` → `pb-find.sh` / `pb-import.sh` / `pb-export.sh`,
seguindo o mesmo padrão de CLI único usado na skill `keycloak-api`, `kc.sh`). Só `pb` fica
symlinkado em `~/.local/bin`; os scripts individuais são internos.

Em `import`/`export`, o identificador do recurso aceita **UUID ou um trecho do nome**
(case-insensitive, resolvido via `scripts/lib.sh:resolve_resource_id`, que roda
`passbolt list resources --json` e filtra por `name`). Se o trecho casar mais de um recurso, o
comando lista os candidatos (nome + id) no erro em vez de adivinhar, e pede para refinar o termo ou
usar o UUID direto.

### `pb find <termo>` — buscar recurso por nome

Lista `id + nome` dos recursos cujo nome contenha o termo (case-insensitive). Só leitura, nunca
expõe secret.

```bash
pb find meu-app
# <resource-id>  MeuApp Dev Env
# <resource-id>  MeuApp Stg Env
```

### `pb import <id-ou-nome> <output-path>` — nota → arquivo, sem ecoar

Baixa a nota/descrição de um recurso e grava direto num arquivo, sem nunca imprimir o conteúdo no
terminal — use para gerar `.env` ou qualquer secret em arquivo, em qualquer repositório.

```bash
pb import <resource-id> ./src/Projeto.Infra.CrossCutting/.env
pb import "meu-app dev" ./src/Projeto.Infra.CrossCutting/.env   # resolve pelo nome
```

Cria o diretório de destino se preciso, pede confirmação antes de sobrescrever, e grava o arquivo
com `chmod 600`.

### `pb export <id-ou-nome> <input-file>` — arquivo → nota, com confirmação

Faz o caminho inverso: sobrescreve a nota/descrição de um recurso no Passbolt com o conteúdo de um
arquivo local. Pede confirmação antes de sobrescrever e nunca imprime o conteúdo do arquivo/nota no
terminal.

```bash
pb export <resource-id> ./src/Projeto.Infra.CrossCutting/.env
pb export "meu-app dev" ./src/Projeto.Infra.CrossCutting/.env   # resolve pelo nome
```

### Disponibilizar o comando fora da skill

Rodar uma vez (symlinka `pb` em `~/.local/bin` — já no PATH — e adiciona o alias equivalente no
`~/.zshrc`; idempotente, pode rodar de novo depois de qualquer alteração nos scripts):

```bash
~/.claude/skills/passbolt-cli/scripts/init.sh
source ~/.zshrc   # ou abrir um novo terminal
```

Depois disso, `pb` funciona em qualquer diretório/shell.


## Troubleshooting

- `passbolt: command not found` — binário fora do `PATH`; reinstalar ou usar `/usr/local/bin/passbolt`.
- Erro de autenticação/certificado — conferir `serveraddress` no TOML e a conectividade
  (`curl -I https://passbolt.example.com`).
- MFA travando em scripts — `--mfaMode noninteractive-totp --mfaTotpToken <seed>`; interativo:
  modo padrão `interactive-totp`.
- Primeira configuração em máquina nova — exportar a chave privada no navegador Passbolt
  (Configurações → Chave privada) antes de rodar `configure`.
