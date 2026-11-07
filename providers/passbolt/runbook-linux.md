# Runbook: Passbolt CLI (`passbolt`) no Linux (Fedora)

Fonte canônica de instalação e configuração do `passbolt` (go-passbolt-cli) nesta máquina. O `arquivos.md` deste diretório trata do uso pelas skills; este runbook trata de como deixar o ambiente pronto. Autenticação, MFA, rotação e diagnóstico profundo ficam em `vault-factory/docs/autenticacao.md`, não repetidos aqui. Escopo: somente Linux (Fedora, dnf). Os caminhos e placeholders seguem o padrão `<...>` para não expor valores reais.

## 1. Escopo e pré-requisitos

- Sistema: Fedora com `dnf` e shell `zsh` (interativo) e `bash` (agentes).
- Conta no cofre Passbolt com acesso aos recursos usados pelas skills.
- Chave privada GPG da conta exportada pela interface web do Passbolt (ver seção 3).
- Passphrase da chave privada, digitada pelo usuário; nunca armazenada em texto fora do arquivo de configuração protegido.
- Acesso `sudo` para instalar o pacote.
- `gpg` e `jq` disponíveis.
- `~/.local/bin` no `PATH`, onde fica o `pb`.

Dois consumidores usam o mesmo CLI:

| Consumidor | Como usa o `passbolt` | Depende de |
|---|---|---|
| Comandos diretos (`passbolt list`, `passbolt get`) | Terminal do usuário | Configuração em `go-passbolt-cli.toml` |
| `pb` (`vault-factory/scripts/pb*.sh`) | Chama `passbolt list resources --json`, `get` e `update` | Mesma configuração, sem flags extras |

## 2. Instalação das dependências

### 2.1 CLI `passbolt` (obrigatório)

Método documentado (RPM do release oficial, versão `0.5.1`):

```bash
VERSAO=0.5.1
BASE=https://github.com/passbolt/go-passbolt-cli/releases/download/v${VERSAO}
RPM=go-passbolt-cli_${VERSAO}_linux_amd64.rpm
curl -fLO "${BASE}/${RPM}"
curl -fLO "${BASE}/<arquivo-de-checksums-do-release>"   # confirmar o nome no release
sha256sum --ignore-missing -c <arquivo-de-checksums-do-release>
sudo dnf install -y "./${RPM}"
```

Para arm64, trocar `amd64` por `arm64`. Confirmar a versão e a URL no repositório oficial (`github.com/passbolt/go-passbolt-cli`) antes de instalar: estes valores vieram do `arquivos.md` e não foram conferidos contra o release.

Alternativa sem RPM (tar.gz, instalação no diretório do usuário):

```bash
tar -xzf "go-passbolt-cli_${VERSAO}_linux_amd64.tar.gz" passbolt
install -m 755 passbolt ~/.local/bin/passbolt
```

Verificação (após instalar):

```bash
command -v passbolt && passbolt --version
rpm -q go-passbolt-cli   # só se instalado pelo RPM
```

Desinstalação: `sudo rpm -e go-passbolt-cli`. Ela **não** remove `~/.config/go-passbolt-cli/` nem `~/.config/passbolt/`.

### 2.2 Script `pb` (obrigatório para as skills)

O `pb` é o atalho de `find`, `import` e `export` da skill `vault-factory`. Vem do repositório, não de pacote:

```bash
~/.config/ai/skills/vault-factory/scripts/init.sh
```

## 3. Credenciais e arquivos locais

### 3.1 Chave privada GPG

1. No navegador, em Configurações → Chave privada, exportar a chave privada da conta.
2. Salvar em `~/.config/passbolt/passbolt_private.asc`, com diretório e arquivo nas permissões exatas:

```bash
umask 077
mkdir -p ~/.config/passbolt
chmod 700 ~/.config/passbolt
# salvar o arquivo exportado em ~/.config/passbolt/passbolt_private.asc
chmod 600 ~/.config/passbolt/passbolt_private.asc
```

Estado esperado:

| Caminho | Permissão | Observação |
|---|---|---|
| `~/.config/passbolt/` | `700` | Diretório da chave exportada |
| `~/.config/passbolt/passbolt_private.asc` | `600` | Chave exportada; conteúdo não lido nem exibido |
| `~/.config/go-passbolt-cli/` | `700` | Diretório da configuração do CLI |
| `~/.config/go-passbolt-cli/go-passbolt-cli.toml` | `600` | Contém a passphrase e (no estado ideal) a chave |

O arquivo `.asc` nunca é lido por humanos nem por agentes: a verificação é só de permissão.

### 3.2 Passphrase

A passphrase que destrava a chave é digitada pelo usuário. Ela vai para o TOML da seção 4.1 e **nunca** para argumento de processo (`--userPassword '...'`), para o histórico do shell nem para arquivo versionado.

## 4. Configuração do estado ideal

### 4.1 Arquivo `go-passbolt-cli.toml`

Criar o arquivo com o editor, sem passar a passphrase por comando:

```bash
umask 077
mkdir -p ~/.config/go-passbolt-cli
chmod 700 ~/.config/go-passbolt-cli
$EDITOR ~/.config/go-passbolt-cli/go-passbolt-cli.toml
chmod 600 ~/.config/go-passbolt-cli/go-passbolt-cli.toml
```

Conteúdo (placeholders no lugar dos valores reais):

```toml
serveraddress = '<servidor-passbolt>'
userpassword = '<passphrase>'
userprivatekey = "<chave-privada-em-uma-linha-com-\n-no-lugar-das-quebras>"
```

- `userprivatekey` embutida é o estado ideal: os scripts `pb` chamam o CLI sem `--userPrivateKeyFile`. Se for omitida, cada comando precisa da flag (ver pendências, seção 8).
- Usar aspas simples ou duplas, mas de forma consistente com o restante do TOML.
- O arquivo não é versionado. Antes de qualquer `git add`, conferir que `go-passbolt-cli.toml` não aparece.

### 4.2 Alternativa: comando `configure`

Use só sem a passphrase na linha de comando. Se o CLI pedir a passphrase de forma interativa, usar esse fluxo; se não pedir, usar o editor da seção 4.1 (confirmar o comportamento, ver seção 8):

```bash
passbolt configure --serverAddress '<servidor-passbolt>' --userPrivateKeyFile ~/.config/passbolt/passbolt_private.asc
```

### 4.3 Shell e `PATH`

Nenhuma variável de ambiente é necessária. O CLI lê tudo do TOML. Não exportar `userpassword` nem a chave em `~/.zshenv`, `~/.zshrc.d/` ou qualquer arquivo carregado pelo shell.

### 4.4 Relação com pass/gopass

A mesma chave GPG pode ser importada no keyring para uso pelo `gopass`/`pass`. O procedimento sem prompt interativo está em `vault-factory/docs/importar-chave-gpg-sem-prompt.md`. Não duplicar a passphrase no keyring fora do necessário.

## 5. Verificação

Nenhum destes comandos imprime segredo. Os nomes de recursos são listados, mas não os conteúdos.

```bash
# 1. CLI instalado (esperado: versão 0.5.1 ou a que o repositório oficial indicar)
command -v passbolt && passbolt --version

# 2. Permissões (esperado: 700, 600 e 600)
stat -c '%a %n' ~/.config/passbolt ~/.config/passbolt/passbolt_private.asc ~/.config/go-passbolt-cli/go-passbolt-cli.toml

# 3. Servidor acessível (esperado: 302)
curl -sS -o /dev/null -w "%{http_code}\n" https://<servidor-passbolt>/

# 4. Autenticação (descarta a saída; se retornar sem erro, o acesso está ok)
passbolt list users >/dev/null && echo OK

# 5. Busca pelo atalho pb: só id e nome, sem conteúdo
pb find <termo>
```

## 6. Troubleshooting

| Sintoma | Causa | Ação |
|---|---|---|
| `passbolt: command not found` | CLI não instalado ou fora do `PATH` | Seção 2.1; conferir `~/.local/bin` no `PATH` |
| `pb` falha logo na primeira chamada | `passbolt` ausente, pois o `pb` depende do CLI | Instalar o CLI (seção 2.1) |
| Erro de autenticação ou certificado | `serveraddress` errado no TOML ou servidor inacessível | Conferir o TOML (com redação, ver abaixo) e o item 3 da seção 5 |
| MFA pedindo código em script | Modo padrão é interativo | Usar o procedimento de MFA em `vault-factory/docs/autenticacao.md`; não passar seed em argumento |
| Chave privada rejeitada | `userprivatekey` mal formatada no TOML (quebras de linha) ou `.asc` de outra conta | Refazer a exportação da chave e reescrever a linha com `\n` |
| Permissão diferente de `600` no TOML | Arquivo criado sem `umask 077` | `chmod 600` e conferir a seção 3.1 |

Para inspecionar o TOML sem expor segredos, redigir antes de exibir:

```bash
sed -E "s/(passphrase|password|key|secret)\s*=\s*['\"].*['\"]/\1=\"***\"/gi" ~/.config/go-passbolt-cli/go-passbolt-cli.toml
```

## 7. Regras de segurança

- **Nunca** imprimir `userpassword`, `userprivatekey`, o conteúdo do `.asc` ou o conteúdo de recursos do cofre no chat, em log ou no histórico do shell.
- **Nunca** passar a passphrase, a seed TOTP ou qualquer segredo como argumento de processo (`--userPassword`, `--mfaTotpToken`): aparecem em `ps` e no histórico.
- **Nunca** versionar `~/.config/passbolt/`, `~/.config/go-passbolt-cli/` ou qualquer `.env` gerado pelos scripts.
- Ao exibir o TOML para diagnóstico, usar a redação da seção 6.
- Se a passphrase ou a chave privada forem expostas (colada em chat, log ou terminal compartilhado): trocar a passphrase na conta Passbolt, exportar nova chave, atualizar o TOML com `chmod 600` e seguir `vault-factory/docs/segredo-exposto.md`.

## 8. Pendências conhecidas

Pontos a confirmar contra o CLI real; as docs evitam passar segredo em argumento de processo enquanto isso.

- **Passphrase em `configure`.** O fluxo documentado roda `passbolt configure` sem `--userPassword`. Confirmar se o CLI pede a passphrase de forma interativa; se não pedir, usar o editor da seção 4.1.
- **Seed TOTP em argumento.** O modo não interativo (`--mfaMode noninteractive-totp`) exige `--mfaTotpToken`, que recebe a seed em argv. Confirmar uma forma de passá-la sem argumento de processo, ou tratar scripts como sem MFA não interativo.
- **Chave privada no TOML versus `--userPrivateKeyFile`.** Os scripts `pb` não passam essa flag, então o estado ideal (chave embutida no TOML) é o que eles exigem. Confirmar com o CLI real.
