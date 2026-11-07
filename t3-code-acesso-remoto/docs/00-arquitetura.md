# 00 — Arquitetura e regras

Leia este arquivo só quando precisar entender o desenho antes de mexer no setup. A tarefa em si está nos módulos listados no [`../SKILL.md`](../SKILL.md).

```
┌─ Celular (app T3 + Tailscale)─┐
│                               │  HTTPS via tailnet
└───────────────┬───────────────┘  https://<host>.<tailnet>.ts.net
                │
   tailscale serve (443) ──► 127.0.0.1:<PORTA_SERVICO>
                                     │
                        serviço T3 persistente
                        Linux: systemd --user, ~/.t3
                        Windows: Tarefa Agendada, %USERPROFILE%\.t3-server
                                     ▲
                                     │ "Add environment" (código de pareamento)
                        app desktop T3 Code
                        diretório separado do servidor
                        Linux: ~/.t3-desktop; Windows: %USERPROFILE%\.t3
                        Settings → Connections: Local environment DESLIGADO
```

## Regras que não podem ser quebradas

- **Um servidor por diretório de dados.** Dois processos com o mesmo `T3CODE_HOME` disputam o estado e o segundo falha com `ServerAlreadyRunningError`. Por isso o desktop usa outro diretório.
- **O servidor escuta só em `127.0.0.1`.** O celular nunca acessa pelo IP; o acesso é pelo nome via `tailscale serve`, porque o certificado é emitido para o nome.
- **O relay do T3 Connect (`relay.t3.codes`) não é usado.** Ele pode estar fora do ar (504); o caminho pela tailnet não depende dele.
- **Não rode `t3` para subir um segundo servidor enquanto o serviço estiver ativo.** Para usar a CLI, conecte ao serviço existente.

## Pré-requisitos

- Binário do T3 no Linux: `~/.t3/bin/t3`. No Windows, use um launcher independente, por exemplo `%USERPROFILE%\.local\bin\t3.cmd`, instalado com `T3CODE_HOME=%USERPROFILE%\.t3-server`.
- Tailscale instalado, logado e `Running` no desktop (`tailscale status --self`).
- MagicDNS ativo na tailnet (sufixo `*.ts.net` em `tailscale status --json` → `MagicDNSSuffix`).
- App Tailscale no celular, logado na mesma conta.

## Particularidades do Windows

- `t3 service` não oferece serviço nativo no Windows na versão instalada. Use uma Tarefa Agendada no logon, oculta, com reinício automático.
- O servidor headless usa uma porta fixa, escolhida por você e passada ao launcher e ao `-Port` do diagnóstico, e `--base-dir %USERPROFILE%\.t3-server`; o desktop pode continuar usando `%USERPROFILE%\.t3` sem disputar estado.
- Autorize o Tailscale Serve uma vez no navegador e grave o proxy em background. Depois disso, a tarefa do T3 sobe somente o servidor local; ela não deve repetir a autorização do Serve.
- Essa persistência começa no logon do usuário. Para iniciar antes do logon seria necessário outro modelo de serviço e credenciais, que não foi validado por este runbook.
