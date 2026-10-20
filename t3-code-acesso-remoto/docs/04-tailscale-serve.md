# 04 — Tailscale Serve para o serviço

1. Exponha o serviço pela tailnet, restrito aos dispositivos da tailnet (não é Funnel):
   ```bash
   tailscale serve --bg --https=443 http://127.0.0.1:<PORTA_SERVICO>
   tailscale serve status
   ```
   A saída deve mostrar `https://<host>.<tailnet>.ts.net (tailnet only)` apontando para `127.0.0.1:<PORTA_SERVICO>`. Exemplo: `https://meu-pc.tailb79344.ts.net` → `http://127.0.0.1:3773`.
2. Se o `serve` já apontava para outra porta, troque: o comando acima sobrescreve a configuração de `/`. Desligue com `tailscale serve --https=443 off`.
3. Teste o endpoint: `curl -sS -o /dev/null -w '%{http_code}\n' https://<host>.<tailnet>.ts.net/.well-known/t3/environment` deve dar `200`.
4. Alternativa: `~/.t3/bin/t3 pair --tailscale --label celular --ttl 15m` publica o serviço pelo Tailscale Serve e já imprime o código com a URL da tailnet. Use essa opção se o passo 1 não for necessário.
