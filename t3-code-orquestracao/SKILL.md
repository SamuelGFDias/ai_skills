---
name: t3-code-orquestracao
description: Usa as ferramentas nativas do servidor MCP t3-code de dentro de uma thread T3 — delegar tarefa a subagente de outro provider (Codex, Claude, OpenCode, Gemini/Antigravity) usando os modelos daquele provider, aplicar papéis do arquiteto (executor/investigador/revisor) na delegação, criar threads independentes ou relacionadas (launch, lote, fork, merge-back, worktree) e clonar repositório do GitLab a partir só do nome do projeto. Use quando, numa sessão do T3 Code, o usuário pedir "passe/delegue isso para o <provider>", "como executor-padrao", "abre uma thread nova/em worktree", "faz um fork", "traz de volta", ou "clona o projeto <nome>".
---

# Skill: t3-code-orquestracao

**Tipo:** internal — testado em 2026-10-21 contra o T3 Code 0.1.1 (ambiente `st-backend-15`). Providers, modelos e flags mudam: o catálogo ao vivo sempre vence o texto desta skill.

Esta skill é um roteador. Carregue **só** o módulo da tarefa.

## Quando executar

- A sessão roda dentro de uma thread T3 (há ferramentas `t3-code`/`t3_code` ou `T3_ACP_MCP_NODE` no ambiente) **e** o pedido envolve delegar, criar/derivar threads, worktree ou clonar projeto.
- Fora do T3, esta skill não se aplica: use os subagentes nativos do harness (ex.: `arquiteto`).

## Roteamento

| Pedido | Ler |
|---|---|
| Achar as ferramentas no harness atual (Claude, OpenCode, Codex, fallback ACP) | [harnesses.md](docs/harnesses.md) |
| "Passe/delegue para o X", escolher provider e modelo | [delegacao.md](docs/delegacao.md) |
| "...como executor-padrao/investigador/revisor" | [delegacao.md](docs/delegacao.md) + [papeis-arquiteto.md](docs/papeis-arquiteto.md) |
| Thread nova, lote, fork, merge-back, worktree, mandar mensagem a outra thread | [threads.md](docs/threads.md) |
| "Clona o projeto <nome>" | [clonagem.md](docs/clonagem.md) + `scripts/localizar-repo.sh` |
| Mapa completo das ferramentas e armadilhas | [ferramentas.md](docs/ferramentas.md) |

## Regras que valem sempre

1. **Catálogo ao vivo antes de delegar ou lançar:** chame `orchestrator_capabilities`. Não use lista de modelos de memória nem desta skill.
2. **O provider vem do nome que o usuário disse, não da família do modelo.** "Codex" → `providerInstanceId: codex`, nunca um GPT servido pelo OpenCode. "Claude" → `claudeAgent`, mesmo estando no OpenCode. Tabela de apelidos em [delegacao.md](docs/delegacao.md).
3. **Provider desabilitado ou modelo ausente: pare e pergunte.** Erro `provider_unavailable` ou modelo fora do catálogo → mostre o que está disponível e pergunte (via `decisoes-com-usuario`). Nunca troque sozinho de provider ou de modelo.
4. **Padrão de "passe para X" sem falar em thread:** `delegate_task` em `mode: async`, checkout compartilhado, `clientRequestId` estável. Thread de topo só quando o usuário pedir thread nova/separada.
5. **Confira o resultado nos metadados, não na resposta do modelo.** O retorno do `delegate_task` (ou `t3_thread_read` da filha) traz `providerInstanceId`/`model`/`options`; o modelo costuma se autodeclarar errado (Haiku respondeu "Opus" no teste).
6. **Não faça polling.** Delegação async acorda esta thread ao terminar; encerre o turno. `task_status` só quando o resultado for necessário no meio do turno.
7. **Decisões do usuário** (destino de clone, candidato ambíguo, provider indisponível, modelo substituto) passam pela skill `decisoes-com-usuario` (que usa `grilling` + a ferramenta de pergunta do harness).
8. **PR criado ou trabalhado na thread:** `link_pull_request` logo em seguida (ver [ferramentas.md](docs/ferramentas.md)).
