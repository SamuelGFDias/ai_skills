# Runbook — instalação do T3 Code v0.1.0 (Linux x86_64)

Release: https://github.com/pingdotgg/t3code/releases/tag/v0.1.0 (publicada em 15/10/2026, marcada como `Latest`).

Este runbook é para uma máquina nova. Ele não foi executado numa máquina limpa; os passos foram conferidos por leitura de release, hash e `--help` do CLI.

## Artefatos conferidos

| Arquivo | Tamanho (bytes) | sha256 |
|---|---|---|
| `T3-Code-0.1.0-x86_64.AppImage` (desktop, Linux x64) | 164052458 | `e38d9c5fb513b1ece0a708b906d3383b5b47ed199575b39a31e41ab8834eb744` |
| `t3-0.1.0-linux-x64.tar.gz` (CLI, Linux x64) | 93550527 | `f7703ff1bb8f6243580058b3ccf2c02abb62eba4b991e26bbb1da22f4b56d9b1` |

Para ARM64 use `T3-Code-0.1.0-arm64.AppImage` e `t3-0.1.0-linux-arm64.tar.gz`. Não confirmado aqui.

O hash do AppImage foi conferido: o arquivo baixado do release bate com o `digest` publicado pela API do GitHub.

## Pré-requisitos

- Linux x86_64 com sessão gráfica (o app desktop é Electron).
- Bibliotecas de sistema. Testado num Fedora 44 mínimo em container descartável: sem elas, o CLI falha com `libatomic.so.1: cannot open shared object file` e o app falha com `libnspr4.so`. Em Fedora, instale:
  ```bash
  sudo dnf install -y libatomic nss nspr atk at-spi2-atk at-spi2-core cups-libs libdrm mesa-libgbm libxkbcommon libXcomposite libXdamage libXrandr libXfixes libXext libxcb alsa-lib pango cairo gtk3
  ```
  Em outras distros, o nome dos pacotes muda. Confira com `ldd <binário> | grep "not found"`.
- FUSE para AppImage. Se o app não abrir reclamando de FUSE, instale `fuse-libs` (Fedora) ou `libfuse2` (Debian/Ubuntu). Alternativa sem FUSE: `APPIMAGE_EXTRACT_AND_RUN=1`. Não testado: o container não tem `/dev/fuse`.
- Pelo menos um agente instalado e logado na mesma máquina (Claude Code ou Codex). O T3 não traz agente próprio.

## 1. Baixar e verificar o hash

```bash
DL=$(mktemp -d)
cd "$DL"
curl -fLO https://github.com/pingdotgg/t3code/releases/download/v0.1.0/T3-Code-0.1.0-x86_64.AppImage
echo "e38d9c5fb513b1ece0a708b906d3383b5b47ed199575b39a31e41ab8834eb744  T3-Code-0.1.0-x86_64.AppImage" | sha256sum -c -
```

Se o `sha256sum -c` não disser `OK`, pare e não instale.

## 2. Instalar no path que os atalhos e wrappers usam

```bash
mkdir -p ~/Applications
install -m 755 "$DL/T3-Code-0.1.0-x86_64.AppImage" ~/Applications/T3-Code.AppImage
```

O nome `T3-Code.AppImage` é o que `~/.t3/bin/t3`, `~/.t3-desktop/bin/t3` e os arquivos `.desktop` esperam. Mudar o nome quebra os wrappers.

## 3. Abrir o app uma vez

Abra pelo menu ou com `~/Applications/T3-Code.AppImage`. O primeiro start cria `~/.t3/`, o wrapper `~/.t3/bin/t3` e o runtime em `~/.t3/runtime/versions/0.1.0/`.

## 4. Confirmar a versão

```bash
~/.t3/bin/t3 --version
ls ~/.t3/runtime/versions/
```

Esperado: `t3 v0.1.0` e a pasta `0.1.0` em `versions/`.

Se o `--version` mostrar outra versão, o runtime pode ter sido atualizado pelo app. Veja o passo de rollback abaixo.

## 5. Serviço em background e desktop separado

Siga os módulos da skill, nesta ordem:

1. [01-servico-background.md](01-servico-background.md): `t3 service install --base-dir <HOME>/.t3` e `systemctl --user enable --now t3code.service`.
2. [02-desktop-diretorio-separado.md](02-desktop-diretorio-separado.md): desktop com `T3CODE_HOME=<HOME>/.t3-desktop`.
3. [03-ambiente-remoto-desktop.md](03-ambiente-remoto-desktop.md): desligar o ambiente local e adicionar o serviço.
4. [04-tailscale-serve.md](04-tailscale-serve.md) e [05-celular.md](05-celular.md) para acesso pelo celular.

## 6. Verificação

```bash
~/.t3/bin/t3 --version                       # 0.1.0
~/.t3/bin/t3 service status                  # instalado, sem pendência
systemctl --user is-enabled t3code.service   # enabled
ss -ltnp | grep 3773                         # porta do serviço (pode variar)
```

Se algum item falhar, consulte [troubleshooting.md](troubleshooting.md).

## Teste em container descartável (validado)

Em `fedora:44`, sem montagens do host, depois de instalar as bibliotecas acima:

- `sha256sum -c` confere os dois artefatos (`OK`).
- `t3-0.1.0-linux-x64.tar.gz` extraído, `cli/t3-0.1.0-linux-x64/t3 --version` → `t3 v0.1.0`.
- `T3-Code-0.1.0-x86_64.AppImage --appimage-extract`, depois `ELECTRON_RUN_AS_NODE=1 squashfs-root/t3code squashfs-root/resources/app.asar/apps/server/dist/bin.mjs --version` → `t3 v0.1.0`. É o mesmo bin que o wrapper `~/.t3/bin/t3` executa.

Não validado no container: o start do app com display, o FUSE e o `t3 service install` (que precisa de systemd de usuário). Também não validado: serviço em `~/.t3` e desktop em `~/.t3-desktop` rodando ao mesmo tempo, e o pareamento de dois clientes (celular e desktop). O teste foi cancelado antes de terminar.

## Alternativa: CLI via npm

O pacote `t3@0.1.0` está publicado no npm (https://www.npmjs.com/package/t3/v/0.1.0). Ele "instala o executável autocontido para esta plataforma". Ainda não foi executado aqui.

```bash
npx t3@0.1.0 --version
```

Use essa opção só se o passo 3 não for possível (por exemplo, máquina sem display). Os passos 4 e 5 continuam valendo.

## Rollback

Se uma versão mais nova foi aplicada e você quer voltar para 0.1.0, use o `t3 update` com `--allow-downgrade`, conforme `t3 update --help`. Não testado aqui:

```bash
~/.t3/bin/t3 update 0.1.0 --allow-downgrade
```

## Riscos conhecidos

- **Crash na GPU em Linux arm64:** a issue https://github.com/pingdotgg/t3code/issues/15591 foi reportada em build anterior a 0.1.0. Não confirmei se ela continua na 0.1.0.
- **Auto-update do app:** o app pode trocar a versão sozinho. Confira `t3 --version` depois de cada abertura.
- **Não rode `t3 uninstall` para trocar de versão.** Ele remove o launcher e todas as versões baixadas, além do serviço. Projetos e threads são mantidos, mas o serviço e os wrappers precisam ser recriados.
