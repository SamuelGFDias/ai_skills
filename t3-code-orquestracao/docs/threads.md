# Threads independentes e relacionadas

Thread de topo (aparece na barra lateral) só quando o usuário pedir thread nova, separada ou conversa própria. "Subagente" ou "paralelo" sozinhos → `delegate_task`.

## Qual ferramenta

| Pedido | Ferramenta | Pontos-chave |
|---|---|---|
| Uma thread nova (em worktree, num projeto, ou scratch) | `t3_thread_launch` | Tarefa vai em `message`. `workspaceStrategy` explícito. Sem ele = **raiz do projeto**, não o worktree atual |
| Várias threads no mesmo checkout desta | `create_threads` | Até 20. Herda projeto/branch/worktree desta thread **sem override** (numa thread scratch, caem no scratch) |
| Derivar desta conversa (ou de outra) | `t3_thread_fork` | `sourcePoint: {type: "latest_stable"}`. Herda configuração e worktree da origem. Retorna `targetThreadId` |
| Devolver contexto de uma thread a outra relacionada | `t3_thread_merge_back` | Mesmo projeto. Vira transferência `pending` até a próxima rodada da thread destino |
| Ver transferências (fork, merge-back, resultado de subagente) | `t3_thread_transfers` | |
| Mandar mensagem a outra thread | `t3_thread_send` | `mode`: `auto` (padrão), `queue`, `steer`, `restart`. `clientRequestId` torna idempotente |
| Esperar/ler outra thread | `t3_thread_wait` / `t3_thread_read` | `wait` não interrompe nada; `read` com `view: activity` mostra chamadas de ferramenta |
| Mover **esta** thread para um worktree novo | `t3_worktree_handoff` | Última ação do turno; use `continuationPrompt`. Falha se a thread já está em worktree |
| Trocar o modelo de uma thread | `t3_thread_configure` | Não muda permissões |
| Pin, snooze, settle, arquivar | `t3_thread_organize` | |

## `workspaceStrategy` do `t3_thread_launch`

```json
{"type": "worktree", "baseRef": "main", "branch": "feature/x", "startFromOrigin": false}
{"type": "existing_worktree", "worktreePath": "/abs/path", "branch": "feature/x"}
{"type": "root"}
```

- Stack de PR: `baseRef` = branch pai, `startFromOrigin: false` (usa commits locais). `startFromOrigin: true` faz fetch e parte do remoto. O padrão do servidor neste ambiente é `true` (`t3_worktree_status.defaultStartFromOrigin`).
- Caminhos de worktree existentes: `t3_worktree_list`.
- `scratch: true` (sem `projectId`) cria thread fora de projeto.
- Modelo: `modelSelection: {"instanceId": "opencode", "model": "opencode/glm-5.3-flash-free"}`. Mesmas regras de provider de [delegacao.md](delegacao.md).
- Não há chave de idempotência: guarde o `threadId`. Se a resposta se perder, confira `t3_thread_list` antes de repetir.
- A thread nova não pode ter modo de runtime/interação mais amplo que esta.

## Referenciar thread ao usuário

`[título](t3-thread://v1/<threadId>)` com o `threadId` exatamente como retornado, sem URL-encode.

## Limpeza

Não existe ferramenta de apagar thread: use `t3_thread_organize` `archive`. `t3_project_delete` com `force: true` remove o projeto e as threads dele; o diretório do repositório **não** é apagado, e worktrees podem sobrar em `~/.t3/worktrees/<pasta-do-projeto>/` (remova com `git worktree remove`, olhando antes).
