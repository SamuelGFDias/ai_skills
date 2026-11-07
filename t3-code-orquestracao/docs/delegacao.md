# Delegar a um subagente (`delegate_task`)

## 1. Catálogo ao vivo

`orchestrator_capabilities` devolve, por provider: `providerInstanceId`, `models[].id`, `models[].options` (IDs e valores aceitos), `runtimeModes`, `canRunChildTask`, `canRunCrossProviderChildTask` e `constraints` (ex.: `"Provider instance is disabled."`). Também traz o provider/modelo/opções herdados desta thread.

## 2. Apelido → `providerInstanceId`

| O usuário diz | `providerInstanceId` | Observação |
|---|---|---|
| codex, gpt, openai | `codex` | **Nunca** um GPT do `opencode` |
| claude, opus, sonnet, haiku, anthropic | `claudeAgent` | **Nunca** `anthropic/*` via OpenCode |
| gemini, antigravity, google | `antigravity` | |
| opencode, deepseek, glm, "modelo grátis" | `opencode` | Hoje o OpenCode do T3 só expõe `opencode/*-free` |
| cursor / grok / pi / muse | `cursor` / `grok` / `pi` / `muse` | |

Apelido de modelo ("haiku", "argon", "glm") → procure o `id` dentro do provider resolvido. Se o nome do modelo só existir em outro provider, **pergunte** em vez de trocar o provider.

## 3. Pré-checagens (parar e perguntar se falharem)

- Provider com `canRunChildTask: false` ou `constraints` "disabled" → avise e pergunte: habilitar o provider no T3 ou escolher outro dos ativos (liste-os). Chamar mesmo assim devolve `provider_unavailable`.
- Modelo pedido fora de `models[].id` → mostre os modelos do provider e pergunte.
- Opção pedida ("max", "rápido") → use só IDs/valores anunciados. Claude: `effort` (`low`…`max`, `ultrathink`), `fastMode` (só Opus). Codex: `reasoningEffort`, `serviceTier`. OpenCode: `variant`. Opção não anunciada → reporte o descompasso, não traduza ("max" não vira "high").
- `isolation: worktree` exige que o checkout pai seja git com commit. Thread em pasta scratch/sem git falha com `Unable to resolve the parent checkout commit` → avise e ofereça checkout compartilhado ou `t3_thread_launch` num projeto.

## 4. Chamada

```json
{
  "task": "<prompt autocontido: objetivo, arquivos, critério de pronto, formato de resposta>",
  "title": "<curto>",
  "target": { "providerInstanceId": "claudeAgent", "model": "claude-haiku-5-5", "options": { "effort": "high" } },
  "mode": "async",
  "isolation": "shared",
  "role": "implementation",
  "clientRequestId": "<estável por rodada, ex.: slug-da-tarefa-r1>"
}
```

- O filho **não** recebe o histórico desta conversa: o `task` tem que ser autocontido.
- `mode: wait` só quando o turno precisa do resultado agora (`timeoutMs` padrão 10 min; estourar **não** cancela o filho).
- `isolation: worktree` cria um checkout a partir do commit local do pai (edições não commitadas **não** vão junto) e roda o setup do projeto. Worktree fica em `~/.t3/worktrees/<pasta-do-projeto>/<branch>`.
- `runtimeMode`: deixe herdar. `approval-required`/`auto-accept-edits` travam o filho esperando aprovação humana. Para limitar o filho, diga isso no `task`.
- Mesmo provider e modelo, sem opções → o subagente nativo do harness serve. Com opções pedidas ou herdadas (`inheritedOptions` não vazio) → `delegate_task`, porque o nativo não aplica opções do T3.

## 5. Depois de delegar

1. Confira no retorno `providerInstanceId`, `model` e `options`. Se não bater com o pedido, reporte.
2. Async: encerre o turno; a conclusão acorda esta thread. Não crie watcher nem polling.
3. `task_status(taskId)` só se precisar do resultado no meio do turno. `task_cancel(taskId)` para parar (para também os netos).
4. Ao relatar ao usuário, diga provider, modelo e opções efetivos, não a autodeclaração do modelo.

## Revisão em rodadas

Cada rodada é um **novo** `delegate_task` com: brief original, achados anteriores, respostas e objeções em aberto, e um `clientRequestId` novo (`...-r2`). Não use `t3_thread_send` no `childThreadId` para abrir nova rodada de revisão.

Follow-up que precisa da conversa do **mesmo** filho (não é rodada de revisão) → `t3_thread_send` no `childThreadId`.
