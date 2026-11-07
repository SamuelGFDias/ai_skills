# Runbook — instalação do T3 Code (Linux x86_64)

Releases e versões disponíveis: https://github.com/pingdotgg/t3code/releases e `npm view t3 dist-tags`. Escolha a versão alvo e use-a no lugar de `<VERSAO>` nos comandos abaixo. Prefira o canal `stable`.

Para atualizar uma instalação que já existe, use [07-upgrade-versao.md](07-upgrade-versao.md), não este runbook.

## Pré-requisitos

- Linux x86_64 com sessão gráfica (o app desktop é Electron). ARM64 usa os artefatos `arm64` da mesma release.
- Bibliotecas de sistema. Sem elas o CLI falha com `libatomic.so.1: cannot open shared object file` e o app com `libnspr4.so`. Os nomes dos pacotes variam por distro. Confira com `ldd <binário> | grep "not found"`. Exemplo para Fedora:
  ```bash
  sudo dnf install -y libatomic nss nspr atk at-spi2-atk at-spi2-core cups-libs libdrm mesa-libgbm libxkbcommon libXcomposite libXdamage libXrandr libXfixes libXext libxcb alsa-lib pango cairo gtk3
  ```
- FUSE para AppImage. Se o app reclamar de FUSE, instale o pacote `fuse-libs` (Fedora) ou `libfuse2` (Debian/Ubuntu). Alternativa sem FUSE: `APPIMAGE_EXTRACT_AND_RUN=1`.
- Pelo menos um agente instalado e logado na mesma máquina (Claude Code ou Codex). O T3 não traz agente próprio.

## 1. Baixar e verificar

```bash
VERSAO=<VERSAO>
DL=$(mktemp -d)
cd "$DL"
curl -fLO "https://github.com/pingdotgg/t3code/releases/download/v$VERSAO/T3-Code-$VERSAO-x86_64.AppImage"
```

Confira o sha256 contra o digest publicado para a release, que a API do GitHub informa:

```bash
gh api "repos/pingdotgg/t3code/releases/tags/v$VERSAO" \
  --jq '.assets[] | select(.name | endswith("x86_64.AppImage")) | .digest'
sha256sum "T3-Code-$VERSAO-x86_64.AppImage"
```

Se os valores não baterem, pare e não instale.

## 2. Instalar no path que os atalhos e wrappers usam

```bash
mkdir -p ~/Applications
install -m 755 "$DL/T3-Code-$VERSAO-x86_64.AppImage" ~/Applications/T3-Code.AppImage
```

O nome `T3-Code.AppImage` é o que `~/.t3/bin/t3`, `~/.t3-desktop/bin/t3` e os arquivos `.desktop` esperam. Mudar o nome quebra os wrappers.

## 3. Abrir o app uma vez

Abra pelo menu ou com `~/Applications/T3-Code.AppImage`. O primeiro start cria `~/.t3/`, o wrapper `~/.t3/bin/t3` e o runtime em `~/.t3/runtime/versions/<VERSAO>/`.

## 4. Confirmar a versão

```bash
~/.t3/bin/t3 --version
ls ~/.t3/runtime/versions/
```

Esperado: a versão alvo no `--version` e a pasta correspondente em `versions/`.

Se o `--version` mostrar outra versão, o app pode ter trocado o runtime sozinho (ver "Riscos" abaixo). Não rode `t3` no PATH para conferir se já existe serviço ativo: ver [troubleshooting.md](troubleshooting.md).

## 5. Serviço em background e desktop separado

Siga os módulos, nesta ordem:

1. [01-servico-background.md](01-servico-background.md): instalar o serviço apontando para `~/.t3`.
2. [02-desktop-diretorio-separado.md](02-desktop-diretorio-separado.md): desktop com `T3CODE_HOME=<HOME>/.t3-desktop`.
3. [03-ambiente-remoto-desktop.md](03-ambiente-remoto-desktop.md): desligar o ambiente local e adicionar o serviço.
4. [04-tailscale-serve.md](04-tailscale-serve.md) e [05-celular.md](05-celular.md): acesso pelo celular.
5. [06-autostart.md](06-autostart.md): subida no boot e no login.

## 6. Verificação

```bash
~/.t3/bin/t3 --version
~/.t3/bin/t3 service status
systemctl --user is-enabled t3code.service   # enabled
ss -ltnp | grep t3code                       # porta do serviço
bash <skill>/scripts/diagnostico.sh          # todas as linhas [OK]
```

Se algum item falhar, consulte [troubleshooting.md](troubleshooting.md).

## Alternativa: CLI via npm

O pacote `t3@<VERSAO>` está publicado no npm. Use só se não for possível abrir o app (por exemplo, máquina sem display). Os passos 4 e 5 continuam valendo.

```bash
npx t3@<VERSAO> --version
```

## Riscos conhecidos

- **Auto-update do app:** o app pode trocar a versão sozinho. Confira `t3 --version` depois de cada abertura.
- **Não rode `t3 uninstall` para trocar de versão.** Ele remove o launcher e todas as versões baixadas, além do serviço. Use [07-upgrade-versao.md](07-upgrade-versao.md).
- **Canal nightly/preview:** não é a versão recomendada para uso diário. Confira os dist-tags com `npm view t3 dist-tags`.
