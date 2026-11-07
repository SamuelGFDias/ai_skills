# Fundamentos: hooks

Pesquisado em 2026-11-07 nas páginas da Anthropic listadas no fim. Base desta skill.

## Hook ou instrução

- O CLAUDE.md é contexto, e não configuração imposta. O modelo lê a instrução e pode não segui-la.
- Hook do tipo `command` ou `http` é determinístico: o harness executa sempre. Hook do tipo `prompt` ou `agent` pede a decisão a outro modelo, então também não é determinístico.
- Sinal para mover uma linha para hook: você continua acrescentando ênfase a ela e o Claude continua errando.
- Para bloquear uma ação qualquer que seja a decisão do Claude, use um hook PreToolUse.
- Mantenha pequeno o conjunto de hooks impostos. Não crie hook para preferência.

## Mecânica do PreToolUse usada no guard.py

- Entrada no stdin: `tool_name` e `tool_input` (em Bash, `tool_input.command`), além de `session_id`, `cwd` e `hook_event_name`.
- Saída: exit 0 com JSON `hookSpecificOutput.permissionDecision` = `deny`, `ask` ou `allow`, e `permissionDecisionReason`.
  - `deny` cancela a chamada e devolve o motivo ao Claude.
  - `ask` mostra o pedido de permissão normal.
  - `allow` pula o pedido, mas não passa por cima das regras de deny das configurações.
- Exit 0 sem JSON não aprova nada: a chamada segue o fluxo normal de permissões.
- Exit 2 bloqueia, e o stderr vai ao Claude. Use exit 2 ou JSON, não os dois.
- Exit diferente de 0 e de 2 é erro não bloqueante: a ação segue. O guard.py falha aberto de propósito.
- O `deny` de um hook vale em todos os modos de permissão.
- Saída extra no stdout (um `echo` no perfil do shell, por exemplo) invalida o JSON em silêncio. Por isso o comando usa `python3 -I`, direto, sem shell de login.

O que vai no CLAUDE.md e o que vai para skill, hook ou rule está em `claude-md/docs/fundamentos.md`.

## Fontes

- https://claude.com/resources/articles/steering-claude-code-skills-hooks-rules-subagents-and-more
- https://code.claude.com/docs/en/best-practices
- https://code.claude.com/docs/en/memory
- https://code.claude.com/docs/en/hooks-guide
- https://code.claude.com/docs/en/hooks
