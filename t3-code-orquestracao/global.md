<!-- desc: Regras de delegação e threads dentro do T3 Code (usa arquiteto + t3-code-orquestracao) -->
## Delegação e orquestração

- **Dentro de uma thread T3 Code** (há ferramentas `t3-code`/`t3_code` ou a variável `T3_ACP_MCP_NODE` no ambiente): para delegar, carregar a skill `arquiteto` e a skill `t3-code-orquestracao` antes de agir. Usar `t3-code-orquestracao` para a delegação e as threads (provider, modelo, worktree, fork, merge-back, clonagem), e `arquiteto` para os papéis e o fluxo de execução.
- **Dentro do T3 Code, não usar o Agent nativo para delegar.** Qualquer pedido de "passa para outro agente", "delega", "subagente" ou equivalente vai para `delegate_task` (`mcp__t3-code__delegate_task`), depois de carregar as skills acima. Só o Agent nativo fica para buscas internas da própria sessão, nunca para delegação.
- **Fora do T3 Code**: para delegar, usar só a skill `arquiteto`. Não carregar `t3-code-orquestracao`.
