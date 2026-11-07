# 05 — Celular (iOS ou Android)

Os nomes exatos dos menus mudam por sistema e versão do app. Os passos abaixo descrevem a intenção: confira cada item no seu aparelho.

1. **App Tailscale** no celular:
   - Logado na mesma conta, com a conexão **ligada** e o ícone de VPN visível.
   - Opção de DNS do Tailscale **ligada** (o app deve indicar que está usando o DNS da tailnet).
   - Se o sistema oferecer subir a VPN sob demanda, ligue para Wi-Fi e dados móveis, para o túnel subir sozinho.
2. Teste a rota a partir do desktop: `tailscale ping -c 3 <nome-do-celular>` deve responder `pong`. Descubra o nome com `tailscale status`. Sem `pong`, o celular não alcança a tailnet e nenhum pareamento vai funcionar.
3. **App T3 Code** no celular: **Add environment**, então:
   - Address: `https://<host>.<tailnet>.ts.net` (use o nome, nunca o IP)
   - Code: o código gerado com `<binário-t3> pair --tailscale` ou com `<binário-t3> pair --base-dir <diretório-do-serviço>`
   - Confirme. Ou escaneie o QR code do desktop.
4. Ao conectar, o ambiente aparece na lista do celular. Os códigos expiram em poucos minutos: se der erro de código, gere outro antes de tentar de novo.
