# Papéis do arquiteto na delegação T3

Papel é **opcional**: só aplique quando o usuário citar um ("passe para o codex como executor-padrao") ou quando a skill `arquiteto` estiver orquestrando dentro do T3. Sem papel citado, delegação simples ([delegacao.md](delegacao.md)).

Fonte dos papéis: `~/.config/ai/skills/arquiteto/roles/<papel>.md`. Fonte dos modelos: `~/.config/ai/skills/arquiteto/cli/<cli>/models.json`. Não copie esses valores para cá: leia os arquivos na hora.

## Montagem da chamada

1. **`task`** = corpo de `roles/<papel>.md` **sem o frontmatter** + linha em branco + `## Subtarefa` + o prompt da subtarefa. Se usar `isolation: worktree`, diga no prompt "você está isolado numa worktree dedicada" (os papéis de executor mudam de regra com isso).
2. **`role`** do `delegate_task`: `executor-*` → `implementation`; `investigador-*` → `research`; `revisor-*` → `review`; `speckit-master` → `research`.
3. **`target`**: provider pedido pelo usuário + modelo/opções traduzidos da tabela abaixo.
4. **`title`**: `<papel>: <resumo>`.

## Tradução `models.json` → catálogo T3

| Provider T3 | Ler | `model` | `options` |
|---|---|---|---|
| `claudeAgent` | `cli/claude/models.json` | `model` igual (ex.: `claude-haiku-5-5`) | `effort` → `{"effort": <valor>}` |
| `codex` | `cli/codex/models.json` | `model` igual (ex.: `gpt-5.4`) | `reasoning` → `{"reasoningEffort": <valor>}` |
| `antigravity` | `cli/antigravity/models.json` (tier) | `flash_lite` → `gemini-3.8-flash-low`; `flash` → `gemini-3.8-flash-high`; `pro` → `gemini-4-argon-high` | nenhuma |
| `opencode` | `cli/opencode/models.json` | procure `opencode/<model>` ou `<model>` no catálogo | nenhuma |

Depois de traduzir, **confirme o ID no catálogo ao vivo** (`orchestrator_capabilities`). Se não existir, pare e pergunte, mostrando os modelos daquele provider. Situação constatada em 2026-10-21: Claude bate direto; OpenCode do T3 só tem `opencode/*-free` (os `deepseek/deepseek-v4-*` do `models.json` não existem lá, então sempre pergunta); Codex está desabilitado.

A tabela de tiers do Antigravity é a única tradução não literal. Se o catálogo mudar os IDs, atualize esta tabela.

## Limites (declarar quando relevantes)

- `disallowedTools` / `readonly` / "sem sub-delegação" do papel **não** são impostos pelo T3: valem só pela instrução no corpo do papel. Para investigador/revisor, reforce no `task`: "não edite arquivos e não chame delegate_task".
- `color` e campos de UI do `models.json` são ignorados.
- O bloco de resposta fixo do papel (`Resultado: ENTREGA | BLOQUEIO` etc.) volta no `summary` da tarefa: leia-o como leria de um subagente nativo.
