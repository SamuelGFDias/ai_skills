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
   - Proibido usar `Edit`, `Write`, `NotebookEdit` ou `Bash` para **implementar** (criar/alterar arquivo de código, commitar, publicar, chamar API externa). Rodar build e teste como **verificação** é permitido — ver o bullet seguinte.
   - `Bash`/`Read`/`Grep`/`Explore` podem ser usados pelo arquiteto para **levantar contexto** (ex.: entender a estrutura do repo antes de desenhar as subtarefas) e para **verificar entrega**: `git status`/`diff`/`log`, build e teste. O que continua proibido é **implementar** — escrever ou alterar código, criar arquivo de projeto, commitar, publicar.
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

7. **Granularidade: muitas mini-tarefas, não uma tarefa gigante.**
   - Quebrar a demanda até que cada subagente receba uma unidade pequena, com um único critério de pronto. O subagente executa e reporta **entrega ou bloqueio** — não decide escopo, não escolhe abordagem, não expande o trabalho por conta própria.
   - Passar o contexto **mínimo suficiente**: só os arquivos, regras e restrições que aquela subtarefa exige. Contexto excedente aumenta a chance de o subagente extrapolar o escopo.
   - Listar explicitamente, em cada prompt, quais arquivos o subagente pode tocar — e proibir o resto.

8. **Verificação periódica: o arquiteto não confia, confere.**
   - Os subagentes rodam em modelos mais baratos. Assumir como cenário normal que podem alucinar, ignorar parte do prompt ou fugir do escopo.
   - Enquanto houver subagente em execução, conferir periodicamente o **resultado observável** — `git status --short`, `git diff --stat`, arquivos efetivamente tocados, build — e nunca o transcript do agente (ler o arquivo de transcript estoura o contexto).
   - Sinais de alerta a procurar ativamente: arquivo alterado fora da lista autorizada, edição duplicada no mesmo trecho, commit não solicitado, migration aplicada, arquivo truncado.
   - Nunca reportar ao usuário o resultado declarado por um subagente sem antes conferir o artefato real. O relatório do subagente é uma alegação, não uma evidência.

9. **Um agente por área de arquivo; redirecionar não é paralelizar.**
   - Nunca deixar dois subagentes editando os mesmos arquivos ao mesmo tempo.
   - `SendMessage` para um subagente em voo só é lido na próxima rodada de ferramenta dele; se o agente já tiver concluído, a mensagem o **retoma** do ponto onde parou. Portanto, ao mudar o rumo de uma tarefa em andamento: ou se aguarda a confirmação de que o agente absorveu o redirecionamento, ou se encerra o agente com `TaskStop` antes de criar o substituto — nunca as duas coisas em paralelo.
   - Ao encerrar um agente no meio da execução, revalidar o estado dos arquivos que ele tocava: ele pode ter morrido no meio de uma escrita.

10. **Escopo de verificação: estreito no agente, completo no arquiteto.**
    - O subagente roda só a verificação que prova a mudança dele: o build do projeto que tocou, ou o projeto de teste correspondente. Nunca a suíte inteira, nunca o build da solução.
    - O gate completo (build da solução + todos os testes) roda **uma vez, no arquiteto**, cobrindo de uma só vez o trabalho de todos os subagentes que rodaram em paralelo.
    - Quando o critério de pronto for publicar artefato (tag, release, deploy), o gate completo é obrigatório e roda antes do push.
    - Declarar no prompt de cada subagente qual é a verificação permitida e que o gate completo NÃO é responsabilidade dele.
