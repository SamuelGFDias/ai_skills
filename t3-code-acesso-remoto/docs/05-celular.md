# 05 — Celular (iPhone)

1. **App Tailscale** (iPhone):
   - Logado na mesma conta, com a chave **ligada** e o ícone de VPN visível na barra de status.
   - **Settings → DNS → Use Tailscale DNS: ligado** (mostra "Using Tailscale DNS").
   - **VPN On Demand: ligado**, com Wi-Fi e Cellular em **Always**, para o túnel subir sozinho.
   - Detect MagicDNS hostnames pode ficar desligado.
2. Teste a rota a partir do desktop: `tailscale ping -c 3 iphone-xr` deve responder `pong`. Sem `pong`, o celular não alcança a tailnet e nenhum pareamento vai funcionar.
3. **App T3 Code** (iPhone): **Add environment**, então:
   - Address: `https://<host>.<tailnet>.ts.net` (use o nome, nunca o IP)
   - Code: o código gerado com `t3 pair --tailscale` ou com `t3 pair --base-dir ~/.t3`
   - Toque em ✓. Ou escaneie o QR code do desktop.
4. Ao conectar, o ambiente aparece na lista do celular. Os códigos expiram em poucos minutos: se der erro de código, gere outro antes de tentar de novo.
