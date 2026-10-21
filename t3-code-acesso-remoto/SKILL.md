---
name: t3-code-acesso-remoto
description: Configura o T3 Code para acesso remoto, com o servidor rodando como serviço em background, o app desktop apontando para outro diretório de dados e o ambiente local desligado, e o celular conectando pela tailnet do Tailscale (sem depender do relay do T3 Connect). Use quando o usuário pedir para instalar o serviço do T3 em background, separar o diretório do desktop, configurar o ambiente remoto no app desktop ou no celular, configurar o Tailscale Serve para o T3, atualizar ou trocar a versão do T3, ou diagnosticar pareamento/conexão do T3 pelo celular.
---

# Skill: t3-code-acesso-remoto

**Tipo:** internal — setup de T3 Code remoto em Linux ou Windows. Esta skill é genérica: nenhum nome de máquina, tailnet, celular, porta ou versão fica fixo nos documentos. Tudo isso é descoberto ou escolhido em tempo de execução (ver "Valores locais").

Esta skill é um roteador. Carregue **só** o módulo da tarefa; não leia a pasta inteira.

## Quando executar

- Diagnosticar qualquer problema do T3: rode primeiro o script somente leitura do sistema operacional (`scripts/diagnostico.sh` no Linux ou `scripts/diagnostico-windows.ps1` no Windows).
- Instalar, configurar ou trocar a versão do T3.

## Valores locais

Os comandos usam marcadores entre `<...>`. Preencha-os com valores desta máquina, nunca com exemplos copiados da documentação:

| Marcador | Como descobrir |
|---|---|
| `<HOME>` | `echo $HOME` (Linux) ou `$env:USERPROFILE` (Windows) |
| `<PORTA_SERVICO>` | `port` em `~/.t3/userdata/server-runtime.json` (Linux); porta escolhida no launcher (Windows) |
| `<host>`, `<tailnet>` | `tailscale status --json`: `Self.DNSName` e `MagicDNSSuffix` |
| `<nome-do-celular>` | `tailscale status`: o nome do dispositivo do celular |
| `<VERSAO>` | Release alvo: `npm view t3 dist-tags` ou a página de releases do T3 |
| `<rótulo-do-celular>`, `<rótulo-do-desktop>` | Nomes livres para identificar cada pareamento |

## Roteamento

| Tarefa | Ler |
|---|---|
| Diagnóstico geral no Linux (primeiro passo) | `scripts/diagnostico.sh`, depois [troubleshooting.md](docs/troubleshooting.md) |
| Diagnóstico geral no Windows (primeiro passo) | `scripts/diagnostico-windows.ps1`, depois [troubleshooting.md](docs/troubleshooting.md) |
| Erro específico (sintoma → causa → ação) | [troubleshooting.md](docs/troubleshooting.md) |
| Entender o desenho e as regras | [00-arquitetura.md](docs/00-arquitetura.md) |
| Instalar o T3 no Linux | [runbook-linux.md](docs/runbook-linux.md) |
| Instalar o T3 no Windows | [runbook-windows.md](docs/runbook-windows.md) |
| Serviço em background (dono de `~/.t3`) | [01-servico-background.md](docs/01-servico-background.md) |
| Desktop com diretório separado (`~/.t3-desktop`) | [02-desktop-diretorio-separado.md](docs/02-desktop-diretorio-separado.md) |
| Desligar o ambiente local e apontar o desktop para o serviço | [03-ambiente-remoto-desktop.md](docs/03-ambiente-remoto-desktop.md) |
| Expor o serviço na tailnet (`tailscale serve`) | [04-tailscale-serve.md](docs/04-tailscale-serve.md) |
| Celular (Tailscale + app T3) | [05-celular.md](docs/05-celular.md) |
| Subida no boot e no login | [06-autostart.md](docs/06-autostart.md) |
| Atualizar ou trocar a versão (upgrade, rollback) | [07-upgrade-versao.md](docs/07-upgrade-versao.md) |

## Regras que não podem ser quebradas

- Um servidor por diretório de dados (`T3CODE_HOME`/`--base-dir`). Não suba `t3` manualmente com o mesmo diretório enquanto o serviço estiver ativo: conecte ao serviço.
- O servidor escuta só em `127.0.0.1`; o celular acessa pelo nome `*.ts.net`, nunca pelo IP.
- Não use o relay do T3 Connect neste setup.
- Não rode `t3 uninstall` para trocar de versão.
- Não grave nomes de máquina, tailnet, celular, IP, porta ou token nos documentos desta skill. Se um valor local precisar ficar registrado, use o arquivo de configuração da máquina, fora deste repositório.

## Verificação final

Rode o diagnóstico do sistema operacional e confirme que não há `[ATENCAO]`. O teste real é abrir o ambiente no desktop e no celular e enviar uma mensagem em cada cliente.
