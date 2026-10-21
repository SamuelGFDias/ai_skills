# Mapa das ferramentas do servidor `t3-code`

Nomes sem prefixo; ver [harnesses.md](harnesses.md) para o prefixo de cada harness. "Thread" = precisa rodar dentro de uma thread T3.

## Catálogo e ambiente

| Ferramenta | Uso | Armadilha |
|---|---|---|
| `orchestrator_capabilities` | Providers, modelos, opções, runtime modes, herança desta thread | Fonte única de verdade; não guardar em cache entre tarefas |
| `t3_environment_read` | Identidade do servidor, preferências (ex.: `newWorktreesStartFromOrigin`) | Não lista modelos |
| `t3_environment_preferences_update` | Muda preferências do ambiente | Escrita compartilhada: confirmar com o usuário |

## Delegação (filhos desta thread)

| Ferramenta | Uso | Armadilha |
|---|---|---|
| `delegate_task` | Subagente de qualquer provider ativo | Ver [delegacao.md](delegacao.md). Filho não herda histórico |
| `task_status` | Estado/resultado de uma tarefa | Não usar em loop; ler resultado terminal confirma a entrega |
| `task_cancel` | Para a tarefa e os netos | |
| `t3_pending_request_list/read/respond` | Perguntas pendentes de um filho (`threadId = childThreadId`) | Não concede aprovação |

## Threads

`t3_thread_launch`, `create_threads`, `t3_thread_fork`, `t3_thread_merge_back`, `t3_thread_transfers`, `t3_thread_send`, `t3_thread_send_attachments`, `t3_thread_wait`, `t3_thread_read`, `t3_thread_list`, `t3_thread_search`, `t3_thread_configure`, `t3_thread_configuration`, `t3_thread_update` (renomear, linkar PR), `t3_thread_organize`, `t3_thread_interrupt`. Detalhes em [threads.md](threads.md).

Fila de mensagens de uma thread: `t3_queue_list/read/edit/reorder/cancel/promote_to_steer`.

## Worktree

| Ferramenta | Uso | Armadilha |
|---|---|---|
| `t3_worktree_status` | Binding desta thread (worktree, branch, raiz, padrão `startFromOrigin`) | Rode antes de `handoff` |
| `t3_worktree_list` | Branches e caminhos de checkout | Worktree detached não aparece |
| `t3_worktree_handoff` | Move **esta** thread para worktree novo | Encerra o turno; use `continuationPrompt`. Para outra thread, use `t3_thread_launch` |

## Projetos

| Ferramenta | Uso | Armadilha |
|---|---|---|
| `t3_project_list` / `t3_project_read` | Projetos registrados e `repositoryIdentity.canonicalKey` | |
| `t3_project_clone` | Só clona | Não registra; destino não vazio dá erro |
| `t3_project_create` | Registra pasta (ou cria repo novo só com `title`) | Workspace já registrado é rejeitado |
| `t3_project_update` | Scripts, modelo padrão | |
| `t3_project_delete` | Remove projeto (`force` se tiver threads) | Não apaga o diretório; worktrees podem sobrar |

Fluxo de clone: [clonagem.md](clonagem.md).

## Pull requests

- Criou ou trabalhou num PR/MR: `link_pull_request` com a URL completa (cada camada de stack). Antes de encerrar, `list_thread_pull_requests` e linkar o que faltar.
- Acompanhar PR: `watch_pull_request` e encerrar o turno (o T3 acorda a thread); ao devolver ao usuário, `unwatch_pull_request`. Não fazer polling.
- Guias de PR do repo: `read_pull_request_guide` / `write_pull_request_guides`.

## Agendamento

`schedule_task` (`schedule` como objeto: `{"type":"interval","everyMs":...}`, `{"type":"fixed_time","timeOfDay":"09:00","weekdays":[1,2,3,4,5]}` ou `{"type":"webhook"}`), `list_scheduled_tasks`, `update_scheduled_task`, `run_scheduled_task_now`, `delete_scheduled_task`. Relatar cadência e próxima execução (ou `webhookUrl`).

## Segredos

`request_secret` → o usuário digita em privado → `secretRef` de uso único. Nunca pedir segredo no chat.

## Visual e preview

- `html_preview` → `html_render`: página HTML autocontida mostrada acima da resposta.
- `preview_*` (navegar, clicar, digitar, snapshot, gravar), `t3_preview_list/close`, `device_*` (simulador/dispositivo): testar app rodando.

## Anexos

`t3_attachment_prepare_upload` / `t3_attachment_discard`: preparar anexos para `t3_thread_launch` ou `t3_thread_send_attachments`.
