# Antigravity CLI (agy): como espera os subagentes

Carregar sob demanda: configurar, regenerar ou diagnosticar os papéis no `agy`. Constatado em 2026-10-19, `agy` 1.4.2, testando o binário (não vem de doc oficial: a doc embutida `agy-customizations` não cobre agentes; a fonte foi `agy changelog`, strings do binário e testes).

## Formato

Agente Markdown customizado: frontmatter YAML + corpo como prompt de sistema. Não é o formato do Gemini CLI.

```markdown
---
name: executor-padrao
description: "Use para ... (uma linha, entre aspas)."
model: flash
subagent: true
---

<corpo do papel = prompt de sistema>
```

- **`model` aceita só um tier:** `inherit | flash_lite | flash | pro`. Qualquer outro valor (inclusive os IDs de `agy models`, como `gemini-3.8-flash-low`) faz o `agy` **descartar o agente em silêncio**: ele some de `agy agent` e `--agent <nome>` responde `unknown agent ... (available: ...)`. O `build-agents.py antigravity` recusa tier inválido por isso.
- O `model` só vale quando o agente é **invocado como subagente** (`invoke_subagent`). Como agente principal (`--agent`) vale o modelo da sessão (`--model`).
- `subagent: true` é aceito; sem ele o agente também carregou nos testes. `kind: local` (Gemini CLI) é tolerado. H1 no corpo não é obrigatório.
- **Não existe campo de esforço** no frontmatter. Outros campos documentados no changelog: `mainAgent`, `hidden`, `inheritMcp`, `commandExecutionPolicy`, `tools`, `skills`, `plugins`, `rules`, `agents`, `hooks`, `excludeDefaultComponents`.
- `description` com `:` precisa ir entre aspas (senão dá `mapping values are not allowed`). O gerador usa `quote_str`.

## Ferramentas (`tools`)

O subagente só recebe o que o frontmatter lista em `tools`; sem a lista o executor ficou sem `run_command` ("ferramenta ausente no escopo"). O `build-agents.py` gera:

- todos os papéis: `run_command, view_file, list_dir, grep_search, find_by_name, send_message`;
- papéis não readonly: mais `write_to_file, replace_file_content, multi_replace_file_content`.

`send_message` é como o subagente devolve o resultado ao pai. `invoke_subagent` fica de fora de propósito (impede sub-delegação, regra 4). Confirmado: o `investigador-padrao` reportou que `write_to_file` não existe no conjunto dele, então o somente-leitura é imposto pela CLI para as ferramentas de arquivo. **Não** impede escrita via `run_command` (ex.: `echo x > arq`).

**Nomes de tool precisam existir no registry dos agentes customizados**, que é menor que a lista do agente principal no evento `init`: `command_status` e `sed_file` aparecem lá, mas fazem o subagente **não iniciar** (`failed to construct executor: ... unknown component: tool "X" not found in registry`). Ao acrescentar uma tool, teste a invocação do subagente.

## MCP codebase-memory

Registro global (uma vez por máquina; grava em `~/.gemini/config/mcp_config.json`):

```bash
agy mcp add codebase-memory ~/.local/bin/codebase-memory-mcp   # agy mcp list -> enabled
```

As tools MCP chegam ao agente pelo meta-tool `call_mcp_tool`. **Não** listar `call_mcp_tool` em `tools:` de agente customizado: não está no registry deles e o subagente não inicia (`unknown component: tool "call_mcp_tool" not found in registry`). Esse tipo de erro aparece localmente, antes de gastar cota: `agy --agent <nome> -p oi` já mostra `failed to construct executor` — serve para validar nomes de `tools` sem modelo.

**Não verificado** (cota esgotada em 2026-10-19): se um subagente com `tools:` restrito enxerga as tools do MCP. O changelog cita `inheritCustomizations` (substituiu `inheritMcp`) como chave que faz o agente adotar skills, rules, plugins, subagents e servidores MCP; os papéis gerados não a usam porque ela pode também herdar subagents, o que conflita com a regra 4. O evento `init` do stream-json lista as mesmas 60 tools para qualquer agente e não serve para essa checagem.

## Permissões em modo headless (`-p`)

`run_command` do subagente é **negado** em `agy -p` (`user denied permission to run command`), porque não há quem aprove. `--mode auto` não está disponível nesta conta. Para executor rodar shell, é preciso sessão interativa com aprovação ou liberar permissões na invocação (`--dangerously-skip-permissions`: decisão do usuário, não testada). Leitura de arquivo só funciona dentro do workspace.

## Onde colocar

| Escopo | Caminho | Observação |
|---|---|---|
| Global | `~/.gemini/config/agents/<nome>.md` ou `.../<nome>/agent.md` | os dois layouts funcionam; é o destino do `sync-agents.sh antigravity` |
| Projeto | `<repo>/.agents/agents/<nome>.md` ou `.../<nome>/agent.md` | repo git com commit; workspace confiável |
| Plugin | `agents/` do plugin ou `agents.json` na raiz | `agy plugin validate` confere |

`~/.gemini/agents/` é do Gemini CLI, **não** do `agy`.

## Delegação

- Agentes definidos no escopo global são **ambient**: o agente padrão do `agy` enxerga todos como subagentes, sem orquestrador dedicado. Basta mandar usar `invoke_subagent` com o nome do papel.
- Um agente principal próprio pode listar `tools: [invoke_subagent]` e `agents: [caminhos]`.
- O subagente devolve o resultado ao pai por `send_message`. O payload do `invoke_subagent` no stream-json traz só `type_name`, `role`, `conversation_id` e `log_uri`; o resultado literal está no `transcript.jsonl` do `log_uri`.

## Como testar

```bash
bin/build-agents.py antigravity && bin/sync-agents.sh antigravity
agy agent                       # deve listar os 9 papéis
agy --output-format stream-json -p "Use invoke_subagent para delegar a <papel>: ..." \
  | python3 -I -c '...'          # step_type=subagent, tool_name=invoke_subagent
```

- Rodar de dentro do diretório que o subagente precisa ler: em `-p` a leitura fora do workspace é **negada** (`user denied permission for read_url/read_file`), e o subagente fica sem resposta.
- O orquestrador em `-p` pode responder antes dos subagentes terminarem; mandar "aguarde os N retornos antes de responder".
- Para ver o tier efetivo: no stream-json o subagente não informa modelo. Pergunte ao próprio subagente ("qual modelo você é?") e compare; no log do CLI aparecem linhas `MODEL_TIER_*`.

## Limites conhecidos

- Cota da conta: o teste de 2026-10-19 terminou em `RESOURCE_EXHAUSTED ... Individual quota reached`. Delegar a vários subagentes gasta cota rápido.
- Execução de shell por executor em `-p` não foi comprovada (negada por permissão); leitura e relato por `investigador-padrao`/`revisor-padrao` foram comprovados.
- O tier `pro` respondeu como Gemini 3.8 Flash na conta testada: pode estar caindo para `flash`. Reconfirmar.
- Somente-leitura dos papéis readonly e proibição de sub-delegação ficam só no texto do prompt (sem allowlist de `tools` validada).
