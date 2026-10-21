# 01 — Serviço em background (dono de `~/.t3`)
> `<HOME>` = seu diretório home absoluto (valor de `echo $HOME`).

Pré-requisito: ver [`../SKILL.md`](../SKILL.md#pré-requisitos).

Versão alvo: a que você escolher (canal `stable` por padrão; `npm view t3 dist-tags` lista os canais). Instalação do zero: [runbook-linux.md](runbook-linux.md). Atualização de versão: [07-upgrade-versao.md](07-upgrade-versao.md).

## Instalação limpa (máquina nova)

1. Instale o AppImage conforme o [runbook](runbook-linux.md), passos 1 e 2 (ou a skill `instalacao-appimage-linux`).
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

## Máquina que já tem o serviço (repair)

Se `t3 service status` disser `needs an update or repair` (a unit aponta para um runtime antigo ou diferente do que você quer), faça o reparo com o binário **explícito** da versão alvo, nunca com o `t3` solto do PATH:

```bash
systemctl --user show t3code.service -p ExecStart --value | grep -o 'versions/[^/]*'   # antes
~/.t3/runtime/versions/<versão-alvo>/t3 service install --base-dir ~/.t3
systemctl --user show t3code.service -p ExecStart --value | grep -o 'versions/[^/]*'   # depois
```

Para trocar de versão de forma normal, use [07-upgrade-versao.md](07-upgrade-versao.md). O `service install` é reparo, não upgrade.

## Diagnóstico de conflito

Se o serviço estiver em loop de `ServerAlreadyRunningError`, outro processo usa o mesmo diretório. Encontre-o pelo `pid` em `~/.t3/userdata/server-runtime.json` e com `ss -ltnp`, e resolva antes de seguir. Ver [`troubleshooting.md`](troubleshooting.md).

## Desinstalação

```bash
~/.t3/bin/t3 service uninstall
```
Isso remove a unit e para o serviço. Projetos e threads são mantidos em `~/.t3`. O `t3 uninstall` remove também o launcher e todas as versões baixadas, então não use para uma simples troca de serviço.
