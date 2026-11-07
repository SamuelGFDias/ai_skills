# Runbook: pass e gopass com GPG no Linux (Fedora)

Fonte canônica de instalação e configuração do `pass` e do `gopass` nesta máquina. O `arquivos.md` deste diretório trata do uso pelas skills; este runbook trata de como deixar o cofre local pronto. Escopo: somente Linux (Fedora, dnf). Os caminhos e placeholders seguem o padrão `<...>` para não expor valores reais.

## 1. Escopo e pré-requisitos

- Sistema: Fedora com `dnf`, shell `zsh` (interativo) e `bash` (agentes).
- Acesso `sudo` para instalar pacotes.
- Chave GPG do usuário, no keyring do GnuPG, com passphrase que só o usuário conhece (ou que está salva pelo `passbolt-cli`, ver seção 3.2).
- `~/.local/bin` no `PATH`, se usar os wrappers de skill.

Papéis:

| Ferramenta | Papel | Estado ideal |
|---|---|---|
| `gpg` (GnuPG 2) | Cifra e decifra os segredos | Obrigatório |
| `pass` | Cofre local, um arquivo GPG por segredo | Obrigatório (usado por `redis-port-forward`, `nuget-factory`) |
| `gopass` | Cofre local compatível com o `pass`, usado no Windows e em algumas skills | Opcional; instalar se a skill exigir |

O cofre `pass`/`gopass` é local. Os segredos compartilhados da equipe ficam no Passbolt (`providers/passbolt/arquivos.md`). A credencial AD pode vir daqui ou do 1Password (`providers/1password/runbook-linux.md`).

## 2. Instalação das dependências

### 2.1 `pass` e GnuPG (obrigatório)

```bash
sudo dnf install pass gnupg2 pinentry
```

Verificação:

```bash
rpm -q pass gnupg2 pinentry    # esperado: pass 1.7.4 ou superior, gnupg2 2.4 ou superior
command -v pass gpg            # esperado: /usr/bin/pass e /usr/bin/gpg
```

### 2.2 `gopass` (opcional)

Pacote do repositório oficial do Fedora (versão 1.17.4 no Fedora 44 em 2026-10-22; confirmar a versão disponível na hora da instalação com `dnf info gopass`):

```bash
sudo dnf install gopass
```

Verificação:

```bash
rpm -q gopass                  # esperado: gopass 1.17.4 ou o que o dnf fornecer
command -v gopass              # esperado: /usr/bin/gopass
```

Se o pacote não estiver disponível no repositório, usar o release oficial do projeto `gopass` (github.com/gopasspw/gopass). Nesse caso, confirmar a versão e a assinatura na fonte oficial antes de instalar. Esse caminho não foi verificado nesta máquina.

## 3. Credenciais (chave GPG)

O `pass` e o `gopass` usam uma chave GPG. A chave privada nunca é lida pelas skills nem exportada em texto claro.

### 3.1 Gerar uma chave nova

Rodar no próprio terminal do usuário, porque o comando pede a passphrase de forma interativa:

```bash
gpg --full-generate-key
```

Escolher o tipo de chave padrão e uma passphrase forte. Guardar a passphrase no gerenciador de senhas corporativo, não em arquivo. Anotar o ID da chave (o campo `sec` do comando da seção 5) e usar o placeholder `<id-da-chave-gpg>` em todos os passos seguintes.

### 3.2 Importar uma chave existente sem prompt

Para a chave que já existe em outro lugar, usar o procedimento de `vault-factory/docs/importar-chave-gpg-sem-prompt.md`. Esse doc cobre o import com passphrase vinda de stdin, o trust da chave e o preset da passphrase no `gpg-agent`. Não duplicar os comandos aqui.

Só usar o fluxo do doc quando a passphrase já estiver salva localmente pelo `passbolt-cli`. Em máquina nova, pedir ao usuário que rode o `gpg --import` interativamente no próprio terminal.

### 3.3 Backup da chave

Sem backup, a perda do disco significa a perda de todos os segredos do cofre.

```bash
# Chave privada: arquivo fora do git, em local seguro (cofre de backup ou mídia offline)
umask 077
gpg --armor --export-secret-keys <id-da-chave-gpg> > <caminho-seguro>/chave-privada.asc

# Certificado de revogação: gerar agora, guardar junto ao backup
gpg --output <caminho-seguro>/revogacao.asc --gen-revoke <id-da-chave-gpg>
```

O arquivo de chave privada é segredo. Nunca copiar para o store, para o repositório dos dotfiles nem para nuvem sem criptografia.

## 4. Configuração do estado ideal

### 4.1 gpg-agent

Arquivo `~/.gnupg/gpg-agent.conf`, com permissões do diretório `700`:

```conf
default-cache-ttl 3600
max-cache-ttl 7200
```

Depois de editar:

```bash
chmod 700 ~/.gnupg
gpgconf --kill gpg-agent
```

O cache permite que várias decifras numa mesma sessão não peçam a passphrase de novo. Para o uso por agente sem TTY e sem popup de pinentry, a configuração completa está em `vault-factory/docs/importar-chave-gpg-sem-prompt.md` (seção "Evitar popups de pinentry").

Em terminal sem janela gráfica, exportar `GPG_TTY` no shell para o pinentry de terminal abrir no lugar certo:

```zsh
export GPG_TTY=$(tty)
```

### 4.2 Inicializar o `pass`

Com a chave já no keyring (seção 3):

```bash
pass init <id-da-chave-gpg>
```

Cria `~/.password-store/` e o arquivo `.gpg-id` com o ID da chave. Com o store já existente, `pass init` troca o `.gpg-id`: rodar só com a chave correta.

Permissão esperada do store:

```bash
chmod 700 ~/.password-store
```

### 4.3 Versionar o store com git

O `pass` grava cada segredo como arquivo `.gpg`. Versionar o diretório permite histórico e recuperação. Não há remoto nesta configuração:

```bash
pass git init
```

Os arquivos do store são cifrados, mas o histórico expõe os **nomes** dos caminhos. Por isso, o remoto do git do store, se houver, deve ser **privado** (ver seção 7).

### 4.4 Inicializar o `gopass`

```bash
gopass init <id-da-chave-gpg>
```

Confirmar a sintaxe na versão instalada com `gopass help init` antes de rodar. O `gopass` tem store próprio, separado do `~/.password-store` do `pass`. Não migrar automaticamente entre os dois.

### 4.5 Estrutura de caminhos

Padrão de caminho usado pelos projetos:

```
<serviço>/<ambiente>/<nome>
```

Exemplos com placeholders: `<serviço>/<ambiente>/senha`, `<serviço>/<ambiente>/token`. Os nomes de serviço e ambiente seguem a convenção de `providers/pass-gopass/arquivos.md`.

### 4.6 Uso pelas skills (inline, sem imprimir)

Consumo do segredo dentro do comando, sem `echo` e sem `pass show` solto:

```bash
REDISCLI_AUTH="$(pass show <serviço>/<ambiente>/senha)" redis-cli ping   # REDISCLI_AUTH, não -a: -a expõe a senha em ps
```

Inserir um segredo sem ecoar o valor:

```bash
read -rs VALOR && printf '%s\n' "$VALOR" | pass insert -e <serviço>/<ambiente>/senha; unset VALOR
```

Com `gopass`, usar `gopass show -o <caminho>` para o valor puro dentro de `$(...)`, e `gopass insert` com entrada por stdin. Confirmar as flags com `gopass help show` e `gopass help insert` na versão instalada.

## 5. Verificação

Nenhum destes comandos imprime segredo.

```bash
# 1. Pacotes e binários
rpm -q pass gnupg2 pinentry
command -v pass gpg

# 2. Chaves secretas no keyring (esperado: 1 ou mais; só a contagem é exibida)
gpg --list-secret-keys --keyid-format long | grep -c '^sec'

# 3. Permissões (esperado: 700 para o diretório do GnuPG e do store)
stat -c '%a %n' ~/.gnupg ~/.password-store

# 4. Store inicializado, só nomes de caminho
pass ls

# 5. Decifra funciona, sem exibir o valor (esperado: OK)
timeout 5 pass show <serviço>/<ambiente>/senha >/dev/null && echo OK

# 6. Somente se o gopass estiver instalado
gopass ls --flat | head -n 5
```

Passo 2 é o teste de que a chave existe. Passo 5 é o teste de que o pinentry e o cache funcionam sem travar.

## 6. Troubleshooting

| Sintoma | Causa | Ação |
|---|---|---|
| `gpg: decryption failed: No secret key` | Chave privada não está no keyring, ou o segredo foi cifrado para outra chave | Importar a chave (seção 3.2) ou conferir o `.gpg-id` do store |
| `Não há garantia de que esta chave pertence a tal utilizador` / `encryption failed: Chave pública inutilizável` | Trust da chave em "desconhecida" | Marcar confiança plena conforme `vault-factory/docs/importar-chave-gpg-sem-prompt.md` (seção "Passo seguinte") |
| `Operação cancelada` / `erro ao enviar para o agent` ao importar | Sem TTY, e o pinentry gráfico não consegue abrir | Usar o fluxo de loopback do doc de importação, ou rodar o comando no terminal do usuário |
| Pinentry não aparece ou trava em terminal | `GPG_TTY` não exportado | `export GPG_TTY=$(tty)` (seção 4.1) |
| `can't connect to '.../S.gpg-agent': Falha na chamada de connect IPC` | `gpg-agent` parado (ex.: depois de `gpgconf --kill`) | Reconectar com `gpg-connect-agent 'GETINFO version' /bye`, ou rodar `gpg` normal antes do comando |
| Popup de passphrase a cada `pass show` | Cache do agent expirou ou `default-cache-ttl` não configurado | Ajustar `~/.gnupg/gpg-agent.conf` (seção 4.1) e `gpgconf --kill gpg-agent` |
| `pass init` falha ou troca o `.gpg-id` sem querer | ID de chave errado ou store existente | Conferir o ID com `gpg --list-secret-keys --keyid-format long`; ver `.gpg-id` antes de rodar `pass init` de novo |
| `Error: password store is empty. Try "pass init".` | Store não inicializado | Rodar `pass init <id-da-chave-gpg>` (seção 4.2) |
| `~/.password-store` com permissão diferente de `700` | Diretório criado com `umask` padrão | `chmod 700 ~/.password-store` |
| `gopass` reclama de store não inicializado | `gopass init` não rodado | Rodar `gopass init <id-da-chave-gpg>` (seção 4.4), se o gopass for usado |
| Segredo aparece no terminal ou no histórico | `pass show` usado sem captura | Trocar por `$(pass show ...)` inline (seção 4.6); se o segredo vazou, seguir a seção 7 |

## 7. Regras de segurança

- **Nunca** imprimir o valor de um segredo (`pass show` sozinho, `echo`, `cat`) no chat, em log ou no histórico do shell.
- **Nunca** passar a passphrase da chave como argumento de processo (`--passphrase`, `-p`). Usar `--passphrase-fd 0` ou o fluxo do doc de importação, que passa pelo stdin.
- **Nunca** colocar a passphrase, a chave privada exportada ou o arquivo de backup em repositório versionado, em `~/.zshenv` ou em nuvem sem criptografia.
- **Nunca** publicar o store em remoto público. O histórico do git do store expõe os nomes dos caminhos. Se houver remoto, ele deve ser privado e de acesso restrito.
- **Nunca** colar a chave privada nem a passphrase no chat. Se a skill precisar dela, pedir ao usuário que rode o comando no próprio terminal.
- Se um segredo do store for exposto: trocar o segredo no serviço de origem, remover a entrada com `pass rm <caminho>` (ou `gopass rm <caminho>`) e registrar a ocorrência conforme o procedimento de segurança da equipe.
- Se a chave privada for exposta: importar o certificado de revogação gerado na seção 3.3 (`gpg --import <caminho-seguro>/revogacao.asc`), gerar outra chave e rodar `pass init <id-da-nova-chave>`, que recifra as entradas existentes para a nova chave.
