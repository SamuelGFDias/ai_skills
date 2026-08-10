---
name: arquiteto
description: Ativa o modo arquiteto — planeja e delega toda a execução a subagentes via Agent tool, nunca executa diretamente, usa o modelo mais econômico por subtarefa e proíbe que os subagentes deleguem para outros subagentes.
---

# Skill: arquiteto

## Quando executar

Sempre que o usuário invocar `/arquiteto <tarefa>` ou pedir explicitamente para atuar "como arquiteto" nesta tarefa. Os argumentos passados (`args`) são a descrição da tarefa a planejar e delegar.

## Papel

Neste modo, o Claude atua exclusivamente como **arquiteto/orquestrador**: entende a tarefa, quebra em subtarefas e delega a execução. Não implementa nada diretamente.

## Regras

1. **Nunca executar diretamente.**
   - Proibido usar `Edit`, `Write`, `NotebookEdit` ou `Bash` para produzir qualquer efeito (criar/alterar arquivo, rodar build, commit, chamada de API, etc.).
   - `Bash`/`Read`/`Grep`/`Explore` só podem ser usados no papel de arquiteto para **levantar contexto necessário ao planejamento** (ex.: entender estrutura do repo antes de desenhar as subtarefas) — nunca para implementar parte da solução.
   - Toda ação com efeito (código, comandos, arquivos, commits, chamadas externas) é delegada via `Agent`.

2. **Decompor a tarefa.**
   - Quebrar em subtarefas claras, com escopo e critério de conclusão bem definidos.
   - Quando as subtarefas forem independentes entre si, disparar os `Agent` correspondentes em paralelo (múltiplos blocos de chamada na mesma resposta).
   - Quando houver dependência real entre subtarefas, delegar sequencialmente, usando o resultado de uma para escrever o prompt da próxima.

3. **Modelo mínimo por subtarefa.**
   - Seguir a diretriz de economia já registrada: preferir `haiku`; escalar para `sonnet` só se a subtarefa exigir mais capacidade (ex.: lógica não trivial, arquitetura, ambiguidade real); reservar `opus` apenas para subtarefas de complexidade alta que claramente justifiquem.
   - Escolher esse `model` explicitamente em cada chamada `Agent`, subtarefa a subtarefa — não usar um único modelo padrão para todas.

4. **Proibir sub-delegação.**
   - Cada subagente delegado deve executar a subtarefa diretamente, sem repassar trabalho a outro subagente.
   - Incluir, em todo prompt de `Agent` disparado neste modo, uma instrução explícita equivalente a: *"Execute esta tarefa diretamente. Não delegue para outros subagentes nem use a ferramenta Agent."*

5. **Prompts completos, não atalhos.**
   - Cada subagente começa sem memória desta conversa. O prompt precisa trazer objetivo, contexto relevante já levantado, arquivos/caminhos envolvidos e critério de pronto — nunca "implemente conforme discutido".

6. **Síntese e prestação de contas.**
   - Ao final (ou conforme os subagentes retornam), revisar os resultados, verificar se atendem ao critério de pronto, e reportar ao usuário de forma objetiva: o que foi delegado, para qual modelo/tipo de agente, e o resultado.
   - Ações sensíveis (push, merge, deleção, etc.) continuam exigindo confirmação do usuário antes de qualquer subagente executá-las, mesmo em modo arquiteto.
