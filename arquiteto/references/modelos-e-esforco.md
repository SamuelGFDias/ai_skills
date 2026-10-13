# Modelos e esforço dos subagentes

Carregar sob demanda: diagnóstico de modelo/custo divergente, ou mudança de configuração por CLI.

## Onde mudar

- **Padrão do repo (versionado):** `cli/<cli>/models.json` → `python3 bin/build-agents.py <cli>`, commitar `dist/` e rodar `bin/sync-agents.sh`.
- **Override pessoal (NÃO versionado):** `cli/<cli>/models.local.json`, mesmo formato, mesclado por papel/campo sobre o `models.json`.
  - Gerar a partir dos defaults: `bin/init-local-models.py <cli> [papéis...]` (sem papéis = todos; deixe só os que vai mudar).
  - Aplicar: `bin/sync-agents.sh <cli>`. Papéis citados viram arquivo real no destino (não acompanham `git pull`); os demais seguem symlink. Mudou o arquivo local ou o `roles/` de um papel sobrescrito: rode o sync de novo. Remover o papel do arquivo e rodar o sync devolve o symlink.
  - `dist/` e `--check` ignoram o arquivo local, então nada pessoal é commitado.
- **Alias vs ID:** o alias `haiku` pode resolver para o Haiku 4.5 (sem níveis de esforço); use `claude-haiku-5-5` para garantir o 5.5.

**Precedência de modelo e esforço no Claude Code** (verificado em 2026-10-06, Claude Code 2.1.292; fonte: docs `sub-agents` e `model-config`):

- **Modelo:** `model` passado na chamada `Agent` > `model` do frontmatter do papel > env `CLAUDE_CODE_SUBAGENT_MODEL` > modelo da sessão. Por isso o arquiteto **não** passa `model` na chamada `Agent` com papel tipado — anularia o mapeamento do `models.json`. Constatado nos transcripts: `executor-mecanico` → `claude-haiku-4-5`, `investigador-padrao` → `claude-sonnet-5-5`, com a sessão em `claude-opus-5-5`.
- **Esforço:** env `CLAUDE_CODE_EFFORT_LEVEL` > `effort` do frontmatter > esforço da sessão (`effortLevel` em `modelSettings` do `settings.json`). Se a env estiver definida, todos os papéis rodam no mesmo esforço — conferir com `env | grep CLAUDE_CODE_` quando o custo divergir do esperado.
- **Haiku ignora `effort`** (não suporta níveis de esforço) — o `effort: low` do `executor-mecanico` é decorativo enquanto o papel estiver em haiku.
- **Como observar:** o transcript não registra o esforço; `/tasks` mostra modelo + esforço na linha de cada subagente. O modelo efetivo pode ser extraído do transcript sem lê-lo inteiro: `grep -o '"model":"[^"]*"' <output_file> | sort | uniq -c`.
- **Atenção:** "Haiku ignora `effort`" vale para o Haiku 4.5; o Haiku 5.5 aceita níveis de esforço (padrão `medium`).
