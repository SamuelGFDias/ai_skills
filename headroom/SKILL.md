---
name: headroom
description: Instala, configura e verifica o Headroom (proxy local de compressão de contexto para agentes de IA) no ambiente local. Cobre o deploy v0.37.0+, onde o roteamento é injetado em rc files de shell (e não no settings.json), a interpretação correta do headroom doctor e como restringir o roteamento ao Claude Code. Use quando o usuário pedir para instalar, configurar, atualizar, diagnosticar ou desinstalar o Headroom.
---

# Skill: headroom

**Tipo:** internal — baseada na máquina local do usuário (valores e caminhos específicos do ambiente).

## O que é

O Headroom é um proxy local de compressão de contexto para agentes de IA (Claude Code, Codex, etc.). Reduz de 10% a 20% dos tokens em sessões de codificação. Proxy principal na porta **8787** (Claude Code); proxy secundário na **8788** (Kilo CLI).

> **IMPORTANTE:** não instalar o `claude-mem` junto com o Headroom — ambos fazem memória persistente entre sessões e vão duplicar contexto e criar duas fontes da verdade divergentes.

## Deploy (v0.37.0+): o que o comando realmente faz

O deploy `headroom deploy` **NÃO injeta nada no `~/.claude/settings.json`**. Ele adiciona blocos de export no fim de `.zshrc`, `.bashrc` e `.profile`:

```bash
export HEADROOM_PORT="8787"
export HEADROOM_HOST="127.0.0.1"
export HEADROOM_MODE="cache"
export HEADROOM_BACKEND="anthropic"
export HEADROOM_TELEMETRY="off"
export ANTHROPIC_BASE_URL="http://127.0.0.1:8787"
```

**Consequência:** o roteamento passa a valer **só em shells novos** (o shell atual não pega as env vars até reabrir). Para verificar o roteamento real, usar:

```bash
zsh -ic 'echo $ANTHROPIC_BASE_URL'   # deve imprimir http://127.0.0.1:8787
```

## Comando de deploy (restrito ao Claude Code)

Para configurar **apenas** o Claude Code (e não copilot/codex/opencode detectados), usar o modo manual:

```bash
headroom deploy \
  --profile default \
  --port 8787 \
  --mode cache \
  --backend anthropic \
  --no-telemetry \
  --memory \
  --providers manual \
  --target claude
```

Flags principais:

| Flag | O que faz |
|------|-----------|
| `--providers manual` | Não detecta alvos automaticamente; exige `--target` |
| `--target claude` | Restringe a configuração ao Claude Code |
| `--mode cache` | Máxima preservação do prefix-cache (~0 busts). Use `token` para compressão mais agressiva |
| `--backend anthropic` | Provedor upstream |
| `--no-telemetry` | Desliga telemetria anônima |
| `--memory` | Ativa memória persistente. **Sem essa flag não há `~/.headroom/memory.db`** e o health check reporta `"memory":{"enabled":false}` |

Para **atualizar** uma instalação existente (trocar `--mode`, adicionar `--memory`), rodar o mesmo comando com o mesmo `--profile`.

## Interpretando o `headroom doctor` (não confiar às cegas)

```bash
headroom doctor
```

O doctor reporta `claude ⚠ warn "not routed (no ANTHROPIC_BASE_URL in settings env)"` **mesmo quando o roteamento está funcionando** — o check lê o env no settings.json, mas o deploy v0.37.0 injeta em rc files de shell. Na mesma saída, `shell env ✓ pass "routed via ANTHROPIC_BASE_URL"` confirma o roteamento real.

**Critério de "ok" correto:**
1. `proxy ✓ pass` em `http://127.0.0.1:8787`
2. `shell env ✓ pass`
3. `zsh -ic 'echo $ANTHROPIC_BASE_URL'` imprime `http://127.0.0.1:8787` (prova empírica do roteamento)
4. `headroom memory stats` com DB criado (se `--memory` foi usado)

O `claude ⚠ warn` isolado não é sinal de problema se o item 3 confirma o roteamento.

Outros avisos conhecidos do doctor (benignos ou informativos): `budget ⚠ warn` (sem budget configurado), `claude remote control ⚠ warn` (Remote Control do Claude desabilitado quando `ANTHROPIC_BASE_URL` aponta para endpoint custom), `claude desktop ⚠ warn` (sessões do Desktop bypassam o proxy).

## Roteando o Kilo CLI pelo proxy (porta 8788)

O Kilo usa gateway próprio (`https://api.kilo.ai/api/gateway`, protocolo OpenAI-compatible), então precisa de um **segundo proxy** Headroom — NÃO rodar `headroom deploy` para isso (reconfiguraria o Claude para a porta nova). Subir container separado:

```bash
docker run -d \
  --name headroom-kilo \
  --restart unless-stopped \
  -p 127.0.0.1:8788:8788 \
  --health-cmd "curl --fail --silent http://127.0.0.1:8788/readyz" \
  --health-interval 30s --health-timeout 5s --health-start-period 20s --health-retries 3 \
  -e HOME=/tmp/headroom-home \
  -e HEADROOM_WORKSPACE_DIR=/tmp/headroom-home/.headroom \
  -e HEADROOM_CONFIG_DIR=/tmp/headroom-home/.headroom/config \
  -v ~/.headroom:/tmp/headroom-home/.headroom \
  ghcr.io/headroomlabs-ai/headroom:latest \
  --host 0.0.0.0 --port 8788 --mode cache \
  --backend anyllm --anyllm-provider openai \
  --openai-api-url https://api.kilo.ai/api/gateway \
  --no-telemetry --memory
```

Depois apontar o Kilo para o proxy no config global (`~/.config/kilo/kilo.jsonc`):

```jsonc
{
  "provider": {
    "kilo": {
      "options": {
        "baseURL": "http://127.0.0.1:8788/v1"
      }
    }
  }
}
```

- O token OAuth do Kilo (em `~/.local/share/kilo/auth.json`) passa direto pelo proxy — nada a configurar de auth.
- **Novas sessões do Kilo** passam pelo proxy (a sessão atual continua direto até reiniciar).
- Se o container `headroom-kilo` cair, o Kilo falha — verificar com `docker ps | grep headroom-kilo`.

## Uso no dia a dia

Nada a fazer: usar o agente normalmente. O proxy comprime o contexto antes de enviar ao provedor e a memória é capturada automaticamente.

```bash
headroom dashboard              # dashboard de economia (proxy precisa estar rodando)
headroom memory list            # lista memórias capturadas
headroom memory list --since 7d # últimas 7 dias
headroom memory edit <id> --content "..."  # corrige uma memória
headroom savings --json         # relatório em JSON
```

## Desinstalar / reverter

```bash
headroom install remove --profile default   # remove deploy + config automática
# remover manualmente os blocos HEADROOM_*/ANTHROPIC_BASE_URL dos rc files
```
