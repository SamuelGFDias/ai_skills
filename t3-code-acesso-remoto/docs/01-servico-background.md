# 01 — Serviço em background (dono de `~/.t3`)
> `<HOME>` = seu diretório home absoluto (valor de `echo $HOME`).

Pré-requisito: ver [`../SKILL.md`](../SKILL.md#pré-requisitos).

Flags conferidas em `t3 service install --help` e `t3 --help` (T3 CLI 0.1.1-nightly). O subcomando `install` ainda não foi executado numa máquina limpa; valide o resultado com os passos de verificação.

## Versão 0.1.0 (release estável, a que vem com o CLI)

Links conferidos na internet e no registry do npm. A instalação por `npx` ainda não foi executada aqui.

- **npm (CLI):** https://www.npmjs.com/package/t3/v/0.1.0. Pacote `t3@0.1.0` publicado, dist-tag `latest`, repositório `pingdotgg/t3code` (`apps/server`).
  ```bash
  npx t3@0.1.0 --version
  ```
- **GitHub (release):** https://github.com/pingdotgg/t3code/releases/tag/v0.1.0. Publicada em 15/10, marcada como `Latest`. AppImage x64 confirmado pela API: `T3-Code-0.1.0-x86_64.AppImage` (sha256 `e38d9c5f…b744`). Runbook completo em [runbook-v0.1.0.md](runbook-v0.1.0.md).
- **Local:** esta máquina tem o runtime `~/.t3/runtime/versions/0.1.0/` (binário de 15/10), que é a versão que veio com o CLI. O AppImage em `~/Applications/` é `0.1.1-nightly`, não 0.1.0.

Não use builds de terceiros (ForkHub, `with-fh`, `ImBIOS`) como se fossem o 0.1.0 oficial.

## Instalação limpa (máquina nova)

1. Instale o AppImage em `<HOME>/Applications/T3-Code.AppImage` (ver skill `instalacao-appimage-linux`).
2. Abra o app desktop uma vez. Ele grava o wrapper `~/.t3/bin/t3` e o runtime em `~/.t3/runtime/`. Confira:
   ```bash
   ~/.t3/bin/t3 --version
   ```
3. Instale o serviço apontando explicitamente para `~/.t3`:
   ```bash
   ~/.t3/bin/t3 service install --base-dir <HOME>/.t3
   ```
4. Garanta que a unit está habilitada e rodando:
   ```bash
   systemctl --user enable --now t3code.service
   ```
5. Verifique:
   ```bash
   ~/.t3/bin/t3 service status
   systemctl --user show t3code.service -p Environment -p ExecStart
   systemctl --user is-enabled t3code.service
   ss -ltnp | grep -E 'node|t3'
   ```
   `service status` deve dizer que o serviço está instalado e sem pendência. A unit precisa ter `T3CODE_HOME=<HOME>/.t3` no `Environment`. Anote a porta do servidor (`<PORTA_SERVICO>`), que vem do `~/.t3/userdata/server-runtime.json`:
   ```bash
   grep -o '"port":[0-9]*' ~/.t3/userdata/server-runtime.json
   ```
   Exemplo deste ambiente: `3773`.

## Máquina que já tem o serviço (repair)

Se `t3 service status` disser `needs an update or repair` (por exemplo, a unit aponta para uma versão antiga em `~/.t3/runtime/versions/`), rode de novo o passo 3 da instalação limpa. O `install` reescreve a unit para a versão ativa. Antes, confira:

```bash
~/.t3/bin/t3 service status
systemctl --user cat t3code.service
```

## Diagnóstico de conflito

Se o serviço estiver em loop de `ServerAlreadyRunningError`, outro processo usa o mesmo diretório. Encontre-o pelo `pid` em `~/.t3/userdata/server-runtime.json` e com `ss -ltnp`, e resolva antes de seguir. Ver [`troubleshooting.md`](troubleshooting.md).

## Desinstalação

```bash
~/.t3/bin/t3 service uninstall
```
Isso remove a unit e para o serviço. Projetos e threads são mantidos em `~/.t3`. O `t3 uninstall` remove também o launcher e todas as versões baixadas, então não use para uma simples troca de serviço.
