# Importar a chave privada do Passbolt no GnuPG sem prompt interativo

Contexto: a chave privada exportada em `~/.config/passbolt/passbolt_private.asc` (ver
`docs/autenticacao.md`) também é o par de chaves usado para inicializar `gopass`/`pass`
(runbook `Runbook — Gopass e Pass` na wiki). Para isso ela precisa estar **importada no keyring
do GnuPG**, não só referenciada por arquivo no TOML do `passbolt-cli`.

## O problema

```bash
gpg --import ~/.config/passbolt/passbolt_private.asc
```

Em sessões sem terminal interativo de verdade (ex.: agente rodando comandos via subprocesso, SSH
sem TTY alocado, alguns terminais de IDE), isso falha assim:

```
gpg: chave ...: chave pública "..." importada
gpg: chave .../...: erro ao enviar para o agent: Operação cancelada
gpg: erro ao ler '...': Operação cancelada
```

A parte pública importa normalmente. A parte **privada** falha porque o `gpg-agent` tenta abrir um
`pinentry` gráfico/interativo para confirmar a operação, e não há onde esse prompt aparecer.

## A solução: passphrase já conhecida + loopback pinentry

Se a passphrase dessa chave já está salva em
`~/.config/go-passbolt-cli/go-passbolt-cli.toml` (campo `userpassword`, usada pelo
`passbolt-cli` — ver `docs/autenticacao.md`), não é preciso pedir a senha de novo ao usuário. Dá
para importar de forma 100% não-interativa, **sem nunca imprimir a passphrase em lugar nenhum**:

### 1. Habilitar loopback pinentry no gpg-agent (uma vez só)

```bash
mkdir -p ~/.gnupg
grep -qxF "allow-loopback-pinentry" ~/.gnupg/gpg-agent.conf 2>/dev/null \
  || echo "allow-loopback-pinentry" >> ~/.gnupg/gpg-agent.conf
chmod 700 ~/.gnupg
gpgconf --kill gpg-agent
```

Isso só *permite* que programas peçam esse modo — não abre nada sozinho, é seguro deixar
permanente.

### 2. Importar com a passphrase vinda direto do TOML, via stdin

```bash
grep -E "^\s*userpassword\s*=" ~/.config/go-passbolt-cli/go-passbolt-cli.toml \
  | sed -E "s/^\s*userpassword\s*=\s*['\"](.*)['\"]\s*\$/\1/" \
  | gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 \
    --import ~/.config/passbolt/passbolt_private.asc
```

Ponto crítico: a passphrase nunca vira variável de shell exposta em `ps`, nunca é passada como
argumento de linha de comando (`--passphrase` faria isso — evitar), e nunca é ecoada/impressa —
ela viaja só pelo pipe (`stdin`, fd 0) entre `sed` e `gpg`.

### 3. Confirmar

```bash
gpg --list-secret-keys --keyid-format long
```

Deve aparecer `sec` (chave secreta) com o UID esperado.

## Passo seguinte quase sempre necessário: trust

Depois de importar, uma tentativa de `pass insert`/`gopass insert` costuma falhar com:

```
gpg: <ID>: Não há garantia de que esta chave pertence a tal utilizador
gpg: [stdin]: encryption failed: Chave pública inutilizável
```

Isso é o GnuPG recusando criptografar para uma chave cuja confiança (`trust`) está
`desconhecida`. Como é a própria chave do usuário, marcar como confiança plena resolve:

```bash
printf "trust\n5\ny\nsave\n" | gpg --batch --yes --command-fd 0 --edit-key <FINGERPRINT>
```

(`5` = "Confio plenamente" no menu do `gpg --edit-key`).

## Evitar popups de pinentry em usos seguintes (`pass show`, `pass insert`, etc.)

Importar a chave resolve só a importação em si. Toda vez que `pass`/`gopass` (ou o próprio `gpg
-d`) precisar decriptar algo depois, o `gpg-agent` volta a pedir a passphrase — por padrão via um
pinentry **gráfico** (`pinentry-gnome3`), que abre um popup na tela do usuário. Isso trava scripts
não-interativos, e mostra ao usuário uma tela pedindo uma senha que ele não tem por quê saber de
cor (ela é gerenciada pela skill, não decorada).

Solução: pré-carregar (preset) a passphrase direto no cache do `gpg-agent`, pela mesma via seca
(pipe, nunca impressa). O cache dura o tempo configurado (`default-cache-ttl`/`max-cache-ttl`) —
depois disso, decriptações usam o cache sem pedir nada de novo.

### 1. Habilitar preset e aumentar o cache (uma vez só)

```bash
grep -qxF "allow-loopback-pinentry" ~/.gnupg/gpg-agent.conf || echo "allow-loopback-pinentry" >> ~/.gnupg/gpg-agent.conf
grep -qxF "allow-preset-passphrase" ~/.gnupg/gpg-agent.conf || echo "allow-preset-passphrase" >> ~/.gnupg/gpg-agent.conf
grep -qxF "default-cache-ttl 3600" ~/.gnupg/gpg-agent.conf || echo "default-cache-ttl 3600" >> ~/.gnupg/gpg-agent.conf
grep -qxF "max-cache-ttl 7200" ~/.gnupg/gpg-agent.conf || echo "max-cache-ttl 7200" >> ~/.gnupg/gpg-agent.conf
gpgconf --kill gpg-agent
```

**Importante em automação/subprocessos:** depois de `gpgconf --kill`, o agent só reaparece quando
algo se conecta a ele de novo (`gpg`, `gpg-connect-agent`). `gpg-preset-passphrase` **não** inicia
o agent sozinho — se rodar logo em seguida sem um passo intermediário que já tenha reconectado,
falha com `can't connect to '.../S.gpg-agent': Falha na chamada de connect IPC`. Garantir que o
agent está de pé antes (`gpg-connect-agent 'GETINFO version' /bye` ou qualquer `gpg` normal) antes
de chamar o preset.

### 2. Descobrir o keygrip da subchave de decriptação

```bash
gpg --list-secret-keys --with-keygrip --keyid-format long
# procurar a linha "ssb ... [E]" (uso E = Encrypt) — é essa que decripta.
# o Keygrip logo abaixo dela é o que importa (não o da chave primária [SC]).
```

### 3. Preset via pipe, sem imprimir a senha

```bash
grep -E "^\s*userpassword\s*=" ~/.config/go-passbolt-cli/go-passbolt-cli.toml \
  | sed -E "s/^\s*userpassword\s*=\s*['\"](.*)['\"]\s*\$/\1/" \
  | /usr/libexec/gpg-preset-passphrase --preset <KEYGRIP_DA_SUBCHAVE_E>
```

(o binário pode estar em `/usr/lib/gnupg/` em vez de `/usr/libexec/` dependendo da distro —
`find /usr -iname gpg-preset-passphrase` se não encontrar de primeira).

### 4. Confirmar

```bash
timeout 5 pass show <qualquer-segredo-existente>   # não deve abrir popup nem travar
```

## Quando usar isso vs. pedir para o usuário digitar a senha

Só usar este fluxo quando a passphrase **já está salva** localmente pelo próprio `passbolt-cli`
(máquina onde ele já foi configurado antes). Numa máquina nova, sem esse TOML ainda, a passphrase
não existe em lugar nenhum além da cabeça do usuário — nesse caso, pedir para ele rodar
`gpg --import` interativamente no próprio terminal dele (fora de qualquer automação), nunca pedir
a senha em texto pelo chat.
