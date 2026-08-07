---
name: ses-gitlab-deps
description: Instala o jq e o glab (CLIs usados pelos scripts SES) em Linux, macOS e Windows (Git Bash), com comandos validados por SO/gerenciador de pacotes e fallback para binários oficiais versionados (glab 1.48.0, jq 1.7). Use quando o usuário pedir para instalar, atualizar ou reparar o jq ou o glab, ou quando um comando do CLI `gitlab-auto-merge` reportar dependência ausente (ex.: saída de `gitlab-auto-merge install`).
---

# Skill: ses-gitlab-deps

## Quando executar

- Pedidos para instalar, atualizar ou reparar `jq` ou `glab`.
- Saída do CLI `gitlab-auto-merge install` (ou `gitlab-auto-merge merge`) indicando
  dependência ausente — o comando gera um prompt que referencia esta skill.
- Qualquer script SES que falhe com `command not found` para `jq`/`glab`.

## Objetivo e regra de ouro (economia de tokens)

Instalar as dependências **sem tentativa e erro**: seguir SEMPRE a ordem abaixo e usar
apenas as URLs validadas desta skill. Não inventar variações de URL nem ficar testando
comandos alternativos.

1. Verificar se a ferramenta já está instalada (`command -v <tool>`).
2. Instalar pelo gerenciador de pacotes nativo, se disponível.
3. Fallback: binário oficial versionado (URLs abaixo).
4. Validar com `<tool> --version`.

## Verificação rápida

```bash
command -v jq && jq --version
command -v glab && glab --version
```

## Detectar o ambiente

```bash
uname -s          # Linux | Darwin | MINGW*/MSYS*/CYGWIN* (Windows/Git Bash)
uname -m          # x86_64/amd64 | aarch64/arm64
. /etc/os-release # $ID e $ID_LIKE (ex.: fedora, ubuntu) quando o arquivo existir
command -v brew apt-get dnf pacman choco scoop
```

## Instalação do jq (versão 1.7)

### Gerenciadores nativos

```bash
brew install jq                          # macOS
sudo apt-get update && sudo apt-get install -y jq   # Debian/Ubuntu
sudo dnf install -y jq                   # Fedora/RHEL
choco install jq -y                      # Windows (Chocolatey)
```

### Binário oficial (fallback)

Base: `https://github.com/jqlang/jq/releases/download/jq-1.7/`

| SO / Arquitetura | Asset | Status |
|------------------|-------|--------|
| linux amd64 | `jq-linux-amd64` | ✅ validado (HTTP 200) |
| linux arm64 | `jq-linux-arm64` | ✅ validado (HTTP 200) |
| macos amd64 | `jq-macos-amd64` | ✅ validado (HTTP 200) |
| macos arm64 | `jq-macos-arm64` | ✅ validado (HTTP 200) |
| windows amd64 | `jq-windows-amd64.exe` | ✅ validado (HTTP 200) |
| windows arm64 | — (asset não existe na 1.7) | usar amd64 ou choco/scoop |

Linux/macOS:

```bash
sudo curl -sSL -o /usr/local/bin/jq https://github.com/jqlang/jq/releases/download/jq-1.7/jq-linux-amd64
sudo chmod +x /usr/local/bin/jq
```

Trocar `jq-linux-amd64` por `jq-linux-arm64`, `jq-macos-amd64` ou `jq-macos-arm64`
conforme o ambiente.

Windows/Git Bash: baixar `jq-windows-amd64.exe` como `jq.exe` para um diretório no
PATH (ex.: `~/.local/bin/`):

```bash
curl -sSL -o ~/.local/bin/jq.exe https://github.com/jqlang/jq/releases/download/jq-1.7/jq-windows-amd64.exe
```

## Instalação do glab (versão 1.48.0)

### Gerenciadores nativos

```bash
brew install glab                                        # macOS
sudo dnf install -y glab                                 # Fedora/RHEL
choco install glab -y                                    # Windows (Chocolatey)
go install gitlab.com/gitlab-org/cli/cmd/glab@latest     # qualquer SO com Go
```

⚠️ No apt (Debian/Ubuntu) normalmente NÃO existe pacote `glab` nos repositórios
padrão — preferir o binário oficial abaixo.

### Binário oficial (fallback)

Base: `https://gitlab.com/gitlab-org/cli/-/releases/v1.48.0/downloads/glab_1.48.0_<os>_<arch>.<ext>`

| SO / Arquitetura | Asset | Status |
|------------------|-------|--------|
| linux amd64 | `glab_1.48.0_linux_amd64.tar.gz` | ✅ validado (HTTP 200) |
| linux arm64 | `glab_1.48.0_linux_arm64.tar.gz` | ✅ validado (HTTP 200) |
| macos amd64 | `glab_1.48.0_darwin_amd64.tar.gz` | ✅ validado (HTTP 200) |
| macos arm64 | `glab_1.48.0_darwin_arm64.tar.gz` | ✅ validado (HTTP 200) |
| windows amd64 | `glab_1.48.0_windows_amd64.zip` | ✅ validado (HTTP 200) |
| windows arm64 | — (asset não existe na 1.48.0) | usar amd64 |

Linux/macOS (o tar.gz contém `bin/glab`):

```bash
curl -sSL -o /tmp/glab.tar.gz https://gitlab.com/gitlab-org/cli/-/releases/v1.48.0/downloads/glab_1.48.0_linux_amd64.tar.gz
tar -xzf /tmp/glab.tar.gz -C /tmp
sudo install -m 755 /tmp/bin/glab /usr/local/bin/glab
rm -rf /tmp/glab.tar.gz /tmp/bin
```

Windows/Git Bash (o zip contém `bin/glab.exe`):

```bash
curl -sSL -o /tmp/glab.zip https://gitlab.com/gitlab-org/cli/-/releases/v1.48.0/downloads/glab_1.48.0_windows_amd64.zip
unzip -o /tmp/glab.zip -d /tmp
mkdir -p ~/.local/bin
cp /tmp/bin/glab.exe ~/.local/bin/glab.exe
```

⚠️ Usar SEMPRE a URL com a versão no nome do arquivo. A URL sem versão
(`downloads/glab_<os>_<arch>.tar.gz`) retorna 404.

## Autenticação do glab na SES-RJ

```bash
glab auth status -h gitlab-prod.saude.rj.gov.br       # verificar
glab auth login --hostname gitlab-prod.saude.rj.gov.br
```

Se o usuário usar o fluxo 1Password, definir `export GLAB_USE_OP_PLUGIN=1` e instalar o
`op` (1password-cli) caso não exista.

## Segurança (obrigatório)

- Baixar binários apenas dos canais oficiais listados acima (GitLab releases / GitHub releases).
- Não instalar via `curl | bash` de fontes não verificadas.
- Não imprimir tokens ou credenciais de autenticação do glab.
