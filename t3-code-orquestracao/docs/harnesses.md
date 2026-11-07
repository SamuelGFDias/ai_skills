# Achar as ferramentas do T3 em cada harness

O servidor MCP se chama `t3-code`. O nome que o agente enxerga depende do harness:

| Harness | Forma do nome | Como carregar |
|---|---|---|
| Claude Code | `mcp__t3-code__<ferramenta>` | Ferramentas deferidas: `ToolSearch` com `select:mcp__t3-code__orchestrator_capabilities,mcp__t3-code__delegate_task,...` (várias numa chamada só) |
| OpenCode | prefixo normalizado pelo harness (ex.: `t3-code_<ferramenta>`) | Já vêm no catálogo de ferramentas. Testado: o OpenCode achou e chamou `orchestrator_capabilities` e `delegate_task` sozinho |
| Codex (code mode) | `tools.mcp__t3_code__<ferramenta>(...)` | Se a varredura inicial não mostrar, tente **uma** chamada direta: `tools.mcp__t3_code__orchestrator_capabilities({})` antes de declarar ausência |
| Qualquer agente ACP sem as ferramentas expostas | terminal | Fallback abaixo |

Servidores MCP opcionais podem conectar tarde. Não declare "T3 indisponível" sem uma tentativa direta.

## Fallback ACP (terminal)

Quando as ferramentas não aparecem e `T3_ACP_MCP_NODE` existe no ambiente:

```bash
ELECTRON_RUN_AS_NODE=1 "$T3_ACP_MCP_NODE" ${T3_ACP_MCP_ENTRYPOINT:+"$T3_ACP_MCP_ENTRYPOINT"} \
  acp-mcp-call orchestrator_capabilities '{}'

ELECTRON_RUN_AS_NODE=1 "$T3_ACP_MCP_NODE" ${T3_ACP_MCP_ENTRYPOINT:+"$T3_ACP_MCP_ENTRYPOINT"} \
  acp-mcp-call delegate_task '{"task":"...","target":{"providerInstanceId":"...","model":"..."},"mode":"async","clientRequestId":"..."}'
```

`T3_ACP_MCP_ENTRYPOINT` fica vazio quando o T3 roda como executável standalone. Esse é o transporte suportado, não um substituto de delegação via shell.

## Ferramenta de pergunta ao usuário

| Harness | Ferramenta |
|---|---|
| Claude Code | `AskUserQuestion` (deferida: `ToolSearch` `select:AskUserQuestion`) |
| Outros | a ferramenta de pergunta estruturada que o harness expõe; sem ela, perguntas numeradas com a recomendação como opção 1 e **parar** |

Detalhe completo na skill `decisoes-com-usuario`.

## Pergunta pendente de um filho

Se `delegate_task` voltar `hasPendingQuestion`, use `t3_pending_request_list` / `t3_pending_request_read` / `t3_pending_request_respond` com `threadId = childThreadId`, ou leve a pergunta ao usuário. `pendingApproval` não dá autoridade de aprovar: leia o pedido completo no filho e deixe a decisão com quem a detém.
