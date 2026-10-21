# 07 — Upgrade de versão

Use este módulo para trocar a versão de uma instalação que já funciona. Para instalação do zero, use [runbook-linux.md](runbook-linux.md) (Linux) ou [runbook-windows.md](runbook-windows.md) (Windows).

## Canais

| Canal | O que é | Quando usar |
|---|---|---|
| `stable` | Release marcada como `Latest` no GitHub; dist-tag `latest` no npm | Padrão. Use este. |
| `preview` | Builds de pré-lançamento (dist-tag `preview`) | Testar algo antes da release |
| `nightly` | Builds diários (dist-tag `nightly`) | Só para quem quer testar mudanças cedo |

Conferir as versões atuais: `npm view t3 dist-tags`.

## 1. Pré-checagens (somente leitura)

```bash
~/.t3/bin/t3 --version                       # versão do wrapper
ls ~/.t3/runtime/versions/                   # runtimes instalados
~/.t3/bin/t3 service status                  # instalado · t3@<versão>
systemctl --user show t3code.service -p ExecStart --value | grep -o 'versions/[^/]*'
```

- `service status` precisa dizer `installed`. Se disser `needs an update or repair`, veja [troubleshooting.md](troubleshooting.md) antes de atualizar.
- O `ExecStart` mostra a versão que o serviço executa hoje. Anote para o rollback.

**Sessões de agente ativas são interrompidas no restart do serviço.** Veja quais estão rodando:

```bash
systemctl --user list-units --all | grep -E 't3code-.*scope'
```

Se houver sessão útil em andamento, espere ela terminar ou avise antes de seguir.

## 2. Backup da unit

```bash
cp ~/.config/systemd/user/t3code.service "$(mktemp -d)/t3code.service.bak"
```

O estado do T3 (projetos, threads) fica em `~/.t3/userdata` e não é alterado pelo `update`. Não é preciso copiar o diretório inteiro para um upgrade normal.

## 3. Atualizar o serviço

Rode o `t3 update` a partir da **CLI mais nova disponível** (o `t3` do PATH, `~/.local/bin/t3`), não do wrapper `~/.t3/bin/t3`. Se o wrapper `~/.t3/bin/t3` estiver em outra versão ou canal, o `t3 update` não o atualiza. Conferir: `command -v t3 && t3 --version`.

```bash
t3 update <versão> --channel <stable|nightly|preview> --base-dir ~/.t3 --yes
```

- `<versão>` é opcional: sem ela, o update pega a mais nova do canal. Para versão exata, informe-a.
- O comando reinicia o serviço. Com `--yes` ele não pede confirmação (obrigatório em script); sem ele, pede antes de reiniciar.
- O aviso "Restarting it interrupts anything running in it" é literal: turnos de agente, terminais e clientes remotos caem. Por isso o passo 1 verifica sessões.
- Não use `t3 service install` para upgrade normal: ele serve para reparo (ver módulo 01).
- O `t3 update` não troca o wrapper `~/.t3/bin/t3`. Enquanto a CLI estiver atrás do serviço, `service status` avisa que o serviço é mais novo que a CLI.

## 4. Confirmar

```bash
t3 --version                                 # CLI do PATH (versão da CLI, não do serviço)
~/.t3/bin/t3 service status                  # installed · t3@<nova versão>
systemctl --user show t3code.service -p ExecStart --value | grep -o 'versions/[^/]*'   # nova versão
curl -s -o /dev/null -w "local %{http_code}\n" http://127.0.0.1:<PORTA_SERVICO>/.well-known/t3/environment
curl -s -o /dev/null -w "tailnet %{http_code}\n" https://<host>.<tailnet>.ts.net/.well-known/t3/environment
bash <skill>/scripts/diagnostico.sh          # todas as linhas [OK]
```

Depois, abra o app desktop e confirme que ele conecta ao serviço. No celular, abra o ambiente e envie uma mensagem de teste.

## 5. Desktop

O app desktop tem o próprio runtime em `~/.t3-desktop` e pode atualizar sozinho. Depois de um upgrade do serviço:

- Se o desktop mostrar uma versão diferente do serviço, feche e reabra o app para ele pegar o runtime novo.
- Para trocar o AppImage, repita o passo 1 do [runbook](runbook-linux.md) com o arquivo novo, substituindo `~/Applications/T3-Code.AppImage`.

## Rollback

Se a nova versão quebrar algo, volte para a anterior usando o número anotado no passo 1:

```bash
t3 update <versão-anterior> --channel <canal-anterior> --base-dir ~/.t3 --allow-downgrade --yes
```

Se o serviço não voltar, reaplique a unit salva no passo 2 e rode `systemctl --user daemon-reload && systemctl --user restart t3code.service`.

## Não faça

- **`t3 uninstall` para trocar de versão.** Remove o launcher, todas as versões baixadas e o serviço.
- **Subir `t3` manualmente enquanto o serviço está ativo.** Vai dar `ServerAlreadyRunningError` ou disputar o mesmo `T3CODE_HOME`.
- **Rodar um binário de versão diferente do serviço para reparar.** Use sempre o caminho explícito do runtime alvo (ver módulo 01).
