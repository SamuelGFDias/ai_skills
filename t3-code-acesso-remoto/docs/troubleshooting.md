# Erros comuns

| Sintoma | Causa provável | Ação |
|---|---|---|
| `ServerAlreadyRunningError` em `boot-service.log` | Desktop e serviço usam o mesmo `T3CODE_HOME` | [02-desktop-diretorio-separado.md](02-desktop-diretorio-separado.md) |
| `t3 service status` diz `needs an update or repair` | Unit aponta para um runtime diferente do que você quer (ex.: versão anterior enquanto o alvo é outra) | Reparo com o binário explícito da versão alvo ([01-servico-background.md](01-servico-background.md)); para upgrade normal, [07-upgrade-versao.md](07-upgrade-versao.md) |
| `t3` no terminal falha com "A T3 Code server is already running for ~/.t3 (pid N, http://127.0.0.1:<PORTA_SERVICO>)" | O serviço `t3code.service` já é dono de `~/.t3`. Típico logo depois do instalador curl, que troca o `t3` do PATH para a versão nova | Não suba outro servidor. Conecte ao serviço (`http://127.0.0.1:<PORTA_SERVICO>` ou o nome `*.ts.net`). Para trocar a versão do serviço, [07-upgrade-versao.md](07-upgrade-versao.md) |
| `t3 --version` (PATH) e `~/.t3/bin/t3 --version` mostram versões diferentes | O `t3` do PATH foi trocado por um instalador; o wrapper `~/.t3/bin/t3` segue o runtime antigo | Confie no `ExecStart` da unit (`systemctl --user show t3code.service -p ExecStart`) para saber o que roda. Alinhar com [07-upgrade-versao.md](07-upgrade-versao.md) |
| No celular: "Failed to fetch remote environment endpoint ... Transport error" | VPN do Tailscale desligada no celular, ou DNS do Tailscale desligado | [05-celular.md](05-celular.md), passos 1 e 2 |
| `tailscale ping <nome-do-celular>` sem resposta | Túnel do celular caído | Religar a conexão do Tailscale no celular, depois ping de novo |
| Erro TLS `internal error` ao acessar pelo IP | Certificado é do nome, não do IP | Usar sempre o nome `*.ts.net` |
| "Relay offline" / 504 do relay | Relay do T3 Connect fora do ar | Não é necessário: usar [04-tailscale-serve.md](04-tailscale-serve.md) e [05-celular.md](05-celular.md) |
| Código de pareamento rejeitado | Código expirou (TTL curto) | Gerar um novo código |
| `serve status` aponta para porta errada | Serve configurado antes do serviço | Repetir o passo 1 de [04-tailscale-serve.md](04-tailscale-serve.md) com a porta correta |
| App não sobe no login | Arquivo de autostart ausente ou `Exec` com caminho errado | Conferir `~/.config/autostart/t3code.desktop` ([06-autostart.md](06-autostart.md)) |
| Windows: `t3 service` informa que o serviço não é suportado | A versão instalada não tem serviço nativo no Windows (ver [00-arquitetura.md](00-arquitetura.md)) | Use a Tarefa Agendada descrita em [runbook-windows.md](runbook-windows.md) |
| Windows: `t3 serve --tailscale-serve` fica esperando ou expira | O Tailscale Serve ainda precisa da autorização inicial no navegador | Rode `tailscale serve --bg --https=443 --yes http://127.0.0.1:<PORTA_SERVICO>`, abra a URL exibida, habilite HTTPS e deixe Funnel desligado; depois suba o T3 sem `--tailscale-serve` |
| Windows: T3 não encontra o Tailscale | A pasta do Tailscale não está no `PATH` do usuário/processo | Adicione o diretório de instalação do Tailscale ao `PATH`, abra um novo terminal e confirme `tailscale version` |
| Celular: endpoint `*.ts.net` não resolve, mas o Serve parece correto | Host ou sufixo da tailnet foi digitado incorretamente | Copie `Self.DNSName` de `tailscale status --json`, remova somente o ponto final e teste exatamente `https://<dns>/.well-known/v3/environment` |
| Windows: Tarefa Agendada está `Ready`, mas a porta não escuta | O script encerrou, o launcher está incorreto ou a ação não usa `--base-dir`/porta fixos | Confira `LastTaskResult`, a ação da tarefa e `%USERPROFILE%\.t3-server\start-t3-server.ps1`; rode `scripts/diagnostico-windows.ps1` |
| Desktop conecta, mas cria outro servidor ou disputa o estado | Desktop e headless apontam para o mesmo diretório | No Windows, mantenha o desktop em `%USERPROFILE%\.t3` e o headless em `%USERPROFILE%\.t3-server`; desligue o ambiente local no desktop depois de validar o remoto |
