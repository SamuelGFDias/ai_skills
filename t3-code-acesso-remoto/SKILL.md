---
name: t3-code-acesso-remoto
description: Configura o T3 Code para acesso remoto, com o servidor rodando como serviço em background, o app desktop apontando para outro diretório de dados e o ambiente local desligado, e o celular conectando pela tailnet do Tailscale (sem depender do relay do T3 Connect). Use quando o usuário pedir para instalar o serviço do T3 em background, separar o diretório do desktop, configurar o ambiente remoto no app desktop ou no celular, configurar o Tailscale Serve para o T3, ou diagnosticar pareamento/conexão do T3 pelo celular.
---

# Skill: t3-code-acesso-remoto

**Tipo:** internal — descreve o setup desta máquina (`pc-ses`, tailnet `tailb79344.ts.net`, celular `iphone-xr`). Valores específicos estão marcados como exemplo.

## Quando executar

- Usuário quer o T3 Code rodando em background, acessível pelo celular.
- Usuário quer o app desktop usando outro diretório de dados e o ambiente local desligado.
- Usuário relata falha de pareamento ou conexão do T3 (celular ou desktop).

Para diagnóstico, rode primeiro `scripts/diagnostico.sh` (somente leitura).

## Arquitetura alvo

```
┌─ iPhone (app T3 + Tailscale) ─┐
│                               │  HTTPS via tailnet
└───────────────┬───────────────┘  https://<host>.<tailnet>.ts.net
                │
   tailscale serve (443) ──► 127.0.0.1:<PORTA_SERVICO>
                                     │
                        serviço T3 (systemd --user, t3code.service)
                        T3CODE_HOME=~/.t3   ← dono do estado do servidor
                                     ▲
                                     │ "Add environment" (código de pareamento)
                        app desktop T3 Code
                        T3CODE_HOME=~/.t3-desktop  ← diretório separado
                        Settings → Connections: Local environment DESLIGADO
```

Regras que não podem ser quebradas:
- **Um servidor por diretório de dados.** Dois processos com o mesmo `T3CODE_HOME` disputam o estado e o segundo falha com `ServerAlreadyRunningError`. Por isso o desktop precisa de outro diretório.
- O servidor escuta só em `127.0.0.1`. O celular nunca acessa pelo IP; o acesso é pelo nome via `tailscale serve`, porque o certificado é emitido para o nome.
- O relay do T3 Connect (`relay.t3.codes`) não é usado nesse setup. Ele pode estar fora do ar (504); o caminho pela tailnet não depende dele.

## Pré-requisitos

- Binário do T3 instalado pelo app desktop: `~/.t3/bin/t3` (wrapper do CLI embutido no AppImage). Confirme com `~/.t3/bin/t3 --version`.
- Tailscale instalado, logado e `Running` no desktop (`tailscale status --self`).
- MagicDNS ativo na tailnet (sufixo `*.ts.net` presente em `tailscale status --json` → `MagicDNSSuffix`).
- App Tailscale no celular, logado na mesma conta.

## Módulos (ordem de execução)

| # | Módulo | Quando usar |
|---|---|---|
| 1 | [docs/01-servico-background.md](docs/01-servico-background.md) | Instalar o serviço que é dono de `~/.t3` |
| 2 | [docs/02-desktop-diretorio-separado.md](docs/02-desktop-diretorio-separado.md) | Fazer o app desktop usar `~/.t3-desktop` |
| 3 | [docs/03-ambiente-remoto-desktop.md](docs/03-ambiente-remoto-desktop.md) | Desligar o ambiente local e apontar o desktop para o serviço |
| 4 | [docs/04-tailscale-serve.md](docs/04-tailscale-serve.md) | Expor o serviço na tailnet via HTTPS |
| 5 | [docs/05-celular.md](docs/05-celular.md) | Configurar o Tailscale e o app T3 no iPhone |
| 6 | [docs/06-autostart.md](docs/06-autostart.md) | Garantir que tudo sobe no boot e no login |
| — | [docs/troubleshooting.md](docs/troubleshooting.md) | Tabela de sintomas e causas |

## Verificação final

Rode `scripts/diagnostico.sh` (somente leitura) e confirme que todas as linhas estão `[OK]`. Só então considere o setup pronto. O teste real é o celular: abrir o ambiente e enviar uma mensagem de teste.
