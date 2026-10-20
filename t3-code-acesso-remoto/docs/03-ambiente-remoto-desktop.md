# 03 — Ambiente remoto no desktop, com ambiente local desligado

1. Gere um código de pareamento para o serviço:
   ```bash
   ~/.t3/bin/t3 pair --base-dir ~/.t3 --label desktop --ttl 15m
   ```
   O código expira. Se der erro, gere outro.
2. No app desktop: **Settings → Connections**.
3. Desligue **Local environment** ("Run agents on this computer"). Assim o desktop não roda agentes no próprio processo e passa a usar só o ambiente remoto.
4. Em **Environments**, clique em **+ Add environment** (ou "Add computer", conforme a versão). Preencha:
   - Address: `http://127.0.0.1:<PORTA_SERVICO>`
   - Code: o código gerado no passo 1
5. Confirme que o ambiente aparece como conectado e que os agentes rodam no serviço (o `~/.t3/userdata/logs` deve registrar a atividade).

## Clientes: um token por dispositivo

Cada dispositivo (desktop, celular) recebe seu próprio token de pareamento, para ser revogado separadamente. Os subcomandos abaixo vêm do `t3 auth --help` e `t3 auth pairing --help` / `t3 auth session --help` (CLI nightly). Os flags de cada subcomando não foram conferidos; rode `--help` antes de usar.

```bash
~/.t3/bin/t3 auth pairing create --help    # token de pareamento de uso único
~/.t3/bin/t3 auth pairing list             # lista tokens ativos, sem revelar o segredo
~/.t3/bin/t3 auth pairing revoke --help    # revoga um token
~/.t3/bin/t3 auth session list             # lista sessões bearer ativas, sem revelar o token
~/.t3/bin/t3 auth session revoke --help    # revoga uma sessão
```

`t3 auth session issue` emite um token bearer com escopo para clientes headless ou remotos. Não validado como alternativa ao pareamento pelo app.

Estado do teste: a validação de dois homes em container (serviço em `~/.t3` e desktop em `~/.t3-desktop` ao mesmo tempo, com dois clientes) foi cancelada antes de terminar. Nada disso foi confirmado.
