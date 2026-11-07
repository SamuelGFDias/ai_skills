# Runbook: 1Password CLI (`op`) no Linux (Fedora)

Fonte canônica de instalação e configuração do `op` nesta máquina. O `arquivos.md` deste diretório trata do uso pelas skills; este runbook trata de como deixar o ambiente pronto. Escopo: somente Linux (Fedora, dnf). Os caminhos e placeholders seguem o padrão `<...>` para não expor valores reais.

O wrapper `op-sa` e o despachante `vault-read` ficam em `vault-factory/scripts/`. O `vault-read` é exposto em `~/.local/bin` por `vault-factory/scripts/init.sh`; o symlink do `op-sa` é criado à mão (seção 4.1).

## 1. Escopo e pré-requisitos

- Sistema: Fedora com `dnf` e shell `zsh` (interativo) e `bash` (agentes).
- Conta 1Password com permissão para criar uma service account e conceder leitura aos cofres usados.
- Acesso `sudo` para instalar o pacote.
- `jq` disponível, para a verificação de nomes de cofres (ver seção 5).
- `~/.local/bin` no `PATH`.

Dois modos de autenticação coexistem:

| Modo | Quem usa | Depende de |
|---|---|---|
| Service account (`op-sa`) | Agentes e shell, sem interação | Arquivo de token local |
| Integração com o app desktop | Uso interativo com biometria | App desktop desbloqueado |

O estado ideal usa a service account. O app desktop é opcional.

## 2. Instalação das dependências

### 2.1 CLI `op` (obrigatório)

Repositório dnf oficial, criado em `/etc/yum.repos.d/1password.repo`:

```ini
[1password]
name="1Password Stable Channel"
baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
```

Instalação:

```bash
sudo dnf install 1password-cli
```

Verificação:

```bash
rpm -q 1password-cli     # esperado: 1password-cli-2.41.0 ou superior
op --version             # esperado: 2.41.0 ou superior
```

O binário fica em `/usr/bin/op`, com dono `root:onepassword-cli`, modo `755` e setgid. Os usuários da máquina **não precisam** estar no grupo `onepassword-cli`: o `op` funciona sem essa associação.

### 2.2 App desktop 1Password (opcional)

Pacote `1password` (8.12.40 nesta máquina). Serve só para uso interativo com biometria.

Para habilitar a integração com o CLI, abrir o app e ir em Configurações > Developer > "Integrate with 1Password CLI". Os nomes de menu variam por versão: confirmar na UI.

Sem o app, o `op` depende apenas da service account (seção 3).

## 3. Service account e token

### 3.1 Criação

1. Em my.1password.com, criar uma service account.
2. Conceder a ela leitura **somente nos cofres necessários** para os agentes e funções (hoje, nesta máquina, os cofres concedidos à service account).
3. Guardar o token gerado no próprio 1Password, não em arquivo de texto.

### 3.2 Arquivos locais

Criar o diretório e o arquivo com as permissões exatas, sem exibir o token:

```bash
mkdir -p ~/.config/op
chmod 700 ~/.config/op
umask 077
$EDITOR ~/.config/op/service-account-token   # colar o token; nunca no histórico nem em argumento
chmod 600 ~/.config/op/service-account-token
op-sa whoami                                  # valida o token (esperado: User Type: SERVICE_ACCOUNT)
```

Estado esperado:

| Caminho | Permissão | Observação |
|---|---|---|
| `~/.config/op/` | `700` | Diretório do token e da config |
| `~/.config/op/service-account-token` | `600` | Token da service account |
| `~/.config/op/config` | `600` | Gerado pelo `op`, sem accounts configuradas |

O token **nunca** vai para `~/.zshenv`, para arquivo versionado nem para argumento de processo.

## 4. Configuração do estado ideal

### 4.1 Wrapper `op-sa`

O `OP_SERVICE_ACCOUNT_TOKEN` não deve ser exportado no ambiente do shell, porque ficaria visível a todo processo filho. O `op-sa` carrega o token do arquivo só para cada chamada. Assim o token também funciona no shell de agente (bash), que não lê `~/.zshenv`.

O wrapper vive no repo (`vault-factory/scripts/op-sa`). Criar o symlink `~/.local/bin/op-sa` apontando para ele. Não copiar o script para `~/.local/bin`: o symlink mantém uma versão só. O `vault-read` também acha o `op-sa` como irmão do próprio script, mesmo sem o symlink.

```bash
ln -sf ~/.config/ai/skills/vault-factory/scripts/op-sa ~/.local/bin/op-sa
chmod +x ~/.config/ai/skills/vault-factory/scripts/op-sa
stat -L -c '%a %n' ~/.local/bin/op-sa    # esperado: 755 (-L segue o symlink)
```

### 4.2 Referências

Guardar só a **referência** de cada segredo (nunca o valor) em variáveis `<SISTEMA>_<SEGREDO>_REF`, por exemplo em `~/.config/ai/refs.env` (modo 600, diretório 700), carregado pelo shell:

```bash
EXEMPLO_API_TOKEN_REF="op://<cofre>/<item>/<campo>"
```

Em shell não interativo (agente em bash), carregar o arquivo antes do uso:

```bash
set -a; . ~/.config/ai/refs.env; set +a
```

A leitura é `vault-read "$EXEMPLO_API_TOKEN_REF"` (contrato em `vault-factory/docs/contrato-provider.md`).

### 4.3 Plugin do Oh-my-zsh

O plugin `1password` do Oh-my-zsh está instalado, mas **não** habilitado em `plugins=()`. Não é necessário para este setup.

## 5. Verificação

Nenhum destes comandos imprime segredo.

```bash
# 1. CLI instalado (esperado 2.41.0 ou superior)
rpm -q 1password-cli
op --version

# 2. Permissões (esperado: 700 no diretório e 600 no token; 755 no alvo do symlink op-sa)
stat -c '%a %n' ~/.config/op ~/.config/op/service-account-token
stat -L -c '%a %n' ~/.local/bin/op-sa

# 3. Identidade da service account (esperado: User Type: SERVICE_ACCOUNT)
op-sa whoami

# 4. Cofres visíveis para a service account, só nomes (esperado: os cofres concedidos à service account)
op-sa vault list --format=json | jq -r '.[].name'

# 5. Leitura de uma referência, sem exibir o valor (exige a variável de referência carregada, ver seção 4.2)
vault-read "$EXEMPLO_API_TOKEN_REF" >/dev/null && echo OK
```

## 6. Troubleshooting

| Sintoma | Causa | Ação |
|---|---|---|
| `authorization prompt dismissed` | Token ausente no ambiente (shell bash de agente) | Usar `op-sa` no lugar de `op` |
| `account is not signed in` | Sem token no ambiente e sem integração do app | Usar `op-sa`, ou habilitar a integração no app desktop |
| Senha com quebra de linha ao passar para outro comando | `op read` escreve `\n` no fim do valor | Usar `tr -d '\n'` antes do pipe (o `vault-read` já não escreve a quebra) |
| Senha visível em `ps` | Senha passada como argumento de processo | Passar a senha por stdin, nunca como argumento |
| `op-sa: token não encontrado` | Arquivo de token ausente ou ilegível | Criar o arquivo de token (seção 3.2) |
| Token com permissão diferente de `600` | Arquivo criado sem `umask 077` ou copiado com outro modo | Recriar o arquivo e rodar `chmod 600` |

## 7. Regras de segurança

- **Nunca** imprimir token ou senha no chat, em log ou no histórico do shell.
- **Nunca** colocar o token em `~/.zshenv`, em arquivo versionado ou em argumento de processo.
- **Nunca** commitar `~/.config/op/`, `~/.config/ai/refs.env` com referências reais ou qualquer arquivo com referências `op://` reais.
- Senha sempre por stdin (`| tr -d '\n' | comando`), nunca por `-p "$(op read ...)"`.
- Se o token ou uma senha for exposto: revogar a service account em my.1password.com, criar outra, gravar o novo token no arquivo (seção 3.2) e trocar a senha afetada.
