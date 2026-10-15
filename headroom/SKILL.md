---
name: headroom
description: Instala, configura e verifica o Headroom (proxy local de compressão de contexto para agentes de IA) no ambiente local. Cobre o deploy v0.37.0+, onde o roteamento é injetado em rc files de shell (e não no settings.json), a interpretação correta do headroom doctor, o modo docker-native (wrapper install.sh) com cache do Kompress, e por que o Kilo CLI não deve ser roteado pelo proxy (gateway multi-provedor). Use quando o usuário pedir para instalar, configurar, atualizar, diagnosticar ou desinstalar o Headroom.
---

# Skill: headroom

**Tipo:** internal — baseada na máquina local do usuário (valores e caminhos específicos do ambiente).

## O que é

O Headroom é um proxy local de compressão de contexto para agentes de IA (Claude Code, Codex, etc.). Reduz de 10% a 20% dos tokens em sessões de codificação. Proxy na porta **8787** (Claude Code). **O Kilo CLI não é roteado** — o gateway dele é multi-provedor e incompatível com o proxy (ver seção própria).

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

### Wrapper docker-native (`install.sh`): o `deploy` não funciona

O subcomando `deploy` é do CLI Python-native. Com o wrapper docker-native (o que o `install.sh`
instala em `~/.local/bin/headroom`) ele roda **dentro** do container e falha ao mutar o rc do
`HOME` (raiz): `[Errno 13] Permission denied: '/tmp/headroom-home/..bashrc...'`. Nesse modo,
instalar com `install apply` e adicionar o bloco de `export`s acima **manualmente**:

```bash
headroom install apply --profile default --port 8787 --backend anthropic \
  --mode cache --memory --no-telemetry --image headroom-ai-local:0.39.0
# + bloco de exports (HEADROOM_*/ANTHROPIC_BASE_URL) em ~/.bashrc (e ~/.profile, ~/.zshrc)
```

`start`/`restart`/`status` reusam a imagem gravada no state. **Não** rodar `install apply` sem
`--image`: ele reverte para `ghcr.io/headroomlabs-ai/headroom:latest`. Se o Kompress/memória
estiverem degradados, ver a receita `docker run` na seção abaixo.

### Kompress: validar a compressão de verdade, não só o health

Proxy "healthy" com `"kompress":{"ready":false,"backend":null}` **não** comprime — o modelo
`chopratejas/kompress-v2-base` (HuggingFace) não baixou. Causa: `HOME=/tmp/headroom-home` é do root,
então o cache do HuggingFace falha com `[Errno 13] Permission denied: '/tmp/headroom-home/.cache'`.
`/health` com `memory.status:"disabled"` tem causa parecida: o DB default fica num caminho sem escrita.

Correção (validada em 2026-10-09, imagem `:latest` 0.36.5, sem imagem derivada): apontar `HF_HOME`,
`XDG_CACHE_HOME` e `HEADROOM_MEMORY_DB_PATH` para dentro do mount `~/.headroom` (gravável). O modelo
(~415 MB) baixa na **primeira requisição** (carga é adiada) e persiste em `~/.headroom/hf`; até lá o
`/health` segue `degraded`. Conferir compressão de verdade nos headers de uma requisição:
`x-headroom-tokens-saved > 0` (um `curl` com chave falsa dá 401 e não prova nada).

### Receita `docker run` (quando `install apply` falha)

`headroom install apply --env HF_HOME=... ` falhou aqui em toda tentativa (`Deployment 'default' did
not become ready after start`, rollback automático, causa não achada — nem sem `--memory`), e deixa
um symlink órfão em `~/.config/systemd/user/default.target.wants/`. Recriar o container à mão
(mesmo nome/porta/restart; trocar uid:gid por `$(id -u):$(id -g)`):

```bash
docker rm -f headroom-default
docker run -d --name headroom-default --restart unless-stopped \
  --user $(id -u):$(id -g) -p 127.0.0.1:8787:8787 \
  -e HOME=/tmp/headroom-home -e HF_HOME=/tmp/headroom-home/.headroom/hf \
  -e XDG_CACHE_HOME=/tmp/headroom-home/.headroom/cache \
  -e HEADROOM_CONFIG_DIR=/tmp/headroom-home/.headroom/config \
  -e HEADROOM_WORKSPACE_DIR=/tmp/headroom-home/.headroom \
  -e HEADROOM_PORT=8787 -e HEADROOM_MODE=cache -e HEADROOM_BACKEND=anthropic \
  -e HEADROOM_TELEMETRY=off -e HEADROOM_MEMORY_ENABLED=1 \
  -e HEADROOM_MEMORY_DB_PATH=/tmp/headroom-home/.headroom/memory.db \
  -v $HOME/.headroom:/tmp/headroom-home/.headroom \
  ghcr.io/headroomlabs-ai/headroom:latest \
  --host 0.0.0.0 --port 8787 --mode cache --backend anthropic --no-telemetry --memory
```

Opcional: montar também `~/.claude`, `~/.codex`, `~/.gemini`, `~/.config/opencode` em
`/tmp/headroom-home/<mesmo caminho>` (o deploy oficial faz isso). Em máquina nova, criar
`~/.headroom` antes e adicionar o bloco de `export`s no rc. **Limite:** o container deixa de ser
gerenciado pelo `headroom install` (`status` não sabe das env vars) e um `install apply` futuro
reverte a correção.

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

**Modo docker-native:** o `headroom doctor` roda dentro de um container efêmero (sem o proxy no seu
próprio localhost e sem o socket do docker), então `proxy ✗ fail` e `deployments ✗ fail down` são
**falsos-negativos** esperados. O check válido nesse modo é `headroom install status --profile default`
(running/ready) + `curl -fsS http://127.0.0.1:8787/readyz`.

Outros avisos conhecidos do doctor (benignos ou informativos): `budget ⚠ warn` (sem budget configurado), `claude remote control ⚠ warn` (Remote Control do Claude desabilitado quando `ANTHROPIC_BASE_URL` aponta para endpoint custom), `claude desktop ⚠ warn` (sessões do Desktop bypassam o proxy).

## Kilo CLI: NÃO rotear pelo proxy (incompatível — gateway multi-provedor)

O Kilo (7.4.22+, fork do opencode) fala com o gateway próprio `https://api.kilo.ai/api/gateway`, mas
**roteia por provedor dentro de um único endpoint**: o cliente manda para sub-rotas do tipo
`/v1/api/openrouter/chat/completions` (um path por provedor upstream). O proxy Headroom só conhece
`/v1/chat/completions` e `/v1/responses`, então remonta o upstream errado e o gateway responde:

```
Bad Request: This endpoint only accepts the path `/chat/completions`.
{"error":"Invalid path","error_type":"invalid_path", ...}
```

**Conclusão:** não configurar `provider.kilo.options.baseURL` apontando para o proxy — o tráfego do
Kilo não é OpenAI-plain. A receita antiga (porta 8788 + `--backend anyllm --openai-api-url
https://api.kilo.ai/api/gateway`) deixou de funcionar e foi removida desta skill.

Para **reverter** um ambiente que já tenha sido roteado:

```bash
docker rm -f headroom-kilo                  # container da 8788, se existir
# remover do ~/.config/kilo/kilo.jsonc o bloco "provider": {"kilo": {...}}
kilo config check                           # valida que a config ficou consistente
```

## Claude Code sem o proxy (Remote Control)

O proxy desativa o Remote Control do Claude (`claude remote control ⚠ warn` no doctor). Para abrir o
Claude **direto** (sem proxy), um override `--settings` zera a `ANTHROPIC_BASE_URL` só naquele
processo — verificado empiricamente: o contador `requests` de `/stats` do proxy não incrementa.

```bash
# ~/.claude/settings-direct.json
{ "env": { "ANTHROPIC_BASE_URL": "" } }
```
```bash
alias claude-direct='claude --settings "$HOME/.claude/settings-direct.json"'
```

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
