# Erros comuns

| Sintoma | Causa provável | Ação |
|---|---|---|
| `ServerAlreadyRunningError` em `boot-service.log` | Desktop e serviço usam o mesmo `T3CODE_HOME` | [02-desktop-diretorio-separado.md](02-desktop-diretorio-separado.md) |
| `t3 service status` diz `needs an update or repair` | Unit aponta para versão antiga do runtime (ex.: `0.1.0` enquanto o ativo é `0.1.1-nightly`) | Rodar `~/.t3/bin/t3 service install --base-dir <HOME>/.t3` e depois `systemctl --user restart t3code.service` ([01-servico-background.md](01-servico-background.md)) |
| No celular: "Failed to fetch remote environment endpoint ... Transport error" | VPN do Tailscale desligada no celular, ou DNS do Tailscale desligado | [05-celular.md](05-celular.md), passos 1 e 2 |
| `tailscale ping iphone-xr` sem resposta | Túnel do celular caído | Religar a chave do Tailscale no celular, depois ping de novo |
| Erro TLS `internal error` ao acessar pelo IP | Certificado é do nome, não do IP | Usar sempre o nome `*.ts.net` |
| "Relay offline" / 504 do relay | Relay do T3 Connect fora do ar | Não é necessário: usar [04-tailscale-serve.md](04-tailscale-serve.md) e [05-celular.md](05-celular.md) |
| Código de pareamento rejeitado | Código expirou (TTL curto) | Gerar um novo código |
| `serve status` aponta para porta errada | Serve configurado antes do serviço | Repetir o passo 1 de [04-tailscale-serve.md](04-tailscale-serve.md) com a porta correta |
| App não sobe no login | Arquivo de autostart ausente ou `Exec` com caminho errado | Conferir `~/.config/autostart/t3code.desktop` ([06-autostart.md](06-autostart.md)) |
