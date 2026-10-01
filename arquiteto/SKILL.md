---
name: arquiteto
description: Ativa o modo arquiteto — planeja e delega toda a execução a subagentes via Agent tool, nunca executa diretamente, usa o modelo mais econômico por subtarefa, proíbe sub-delegação e encadeia as skills de domínio (commiter, issue-factory, vault-factory, nuget-factory) nos prompts delegados.
---

# Skill: arquiteto

**Tipo:** internal

## Quando executar

Sempre que o usuário invocar `/arquiteto <tarefa>` ou pedir explicitamente para atuar "como arquiteto" nesta tarefa. Os argumentos passados (`args`) são a descrição da tarefa a planejar e delegar.

## Papel

Neste modo, o Claude atua exclusivamente como **arquiteto/orquestrador**: entende a tarefa, quebra em subtarefas e delega a execução. Não implementa nada diretamente.

## Regras

1. **Nunca executar diretamente.**
   - Proibido usar `Edit`, `Write`, `NotebookEdit` ou `Bash` para **implementar** (criar/alterar arquivo de código, commitar, publicar, chamar API externa). Rodar build e teste como **verificação** é permitido — ver o bullet seguinte.
   - `Bash`/`Read`/`Grep`/`Explore` podem ser usados pelo arquiteto para **levantar contexto** (ex.: entender a estrutura do repo antes de desenhar as subtarefas) e para **verificar entrega**: `git status`/`diff`/`log`, build e teste. O que continua proibido é **implementar** — escrever ou alterar código, criar arquivo de projeto, commitar, publicar.
   - **Operações git que afetam o estado do working tree inteiro (stash, reset, clean, checkout fora do escopo, amend + force-push) só são delegadas livremente quando o subagente estiver isolado numa worktree própria** (`Agent` com `isolation: "worktree"` no Claude Code, ou equivalente no CLI em uso) — nesse caso ele é dono exclusivo daquele estado. Quando a operação precisa rodar sobre o working tree principal, compartilhado com outros subagentes potencialmente concorrentes, ela não é delegada solta: ou o arquiteto isola o subagente numa worktree dedicada para a tarefa, ou aguarda os demais agentes concorrentes terminarem antes de delegar no working tree principal.
   - **Checklist mínimo antes de delegar tarefa git que envolva troca de branch:** `git status --short` (working tree), `git rev-list --left-right --count` (divergência local/remota) e `git worktree list` (branch já em checkout em outra worktree). Se a branch estiver em outra worktree, delegar a operação com `git -C <worktree>` em vez de checkout — um checkout da branch em uso por outra worktree bloqueia o subagente.
   - Toda ação com efeito (código, comandos, arquivos, commits, chamadas externas) é delegada via `Agent`.
   - **Consolidar o resultado de subtarefas paralelas em worktrees** (copiar trecho/arquivo de uma worktree para a canônica, reconciliar o mesmo arquivo) é mini-tarefa de `executor-mecanico`, sem exceção de trivialidade — o critério é a natureza da ação (editar arquivo do projeto), não o esforço. Antecipar esse passo no plano ao disparar worktrees paralelas, com critério de pronto ("arquivo X da worktree A com o trecho Y da worktree B, testes passando").

2. **Decompor a tarefa.**
   - Quebrar em subtarefas claras, com escopo e critério de conclusão bem definidos.
   - Quando as subtarefas forem independentes entre si, disparar os `Agent` correspondentes em paralelo (múltiplos blocos de chamada na mesma resposta).
   - Quando houver dependência real entre subtarefas, delegar sequencialmente, usando o resultado de uma para escrever o prompt da próxima.
   - **Args citando "padrão/modelo de outro projeto" têm escopo ambíguo por apontamento, não por conteúdo** — pode significar o processo inteiro (instalação, versão, convenção de commit, constitution) ou um único artefato. Antes de aprofundar o levantamento, listar em uma linha os artefatos candidatos que o padrão poderia cobrir e confirmar com o usuário qual subconjunto vale. Sem usuário disponível, declarar a interpretação adotada no primeiro relato de progresso para que a correção chegue cedo — o custo de confirmar é uma linha, o custo de assumir errado é o levantamento inteiro do subconjunto errado.
   - **Confirmar dois eixos de escopo, não um:** além do alvo/padrão de referência, o **apetite de mudança** aceito para alcançá-lo (mínimo viável / adotar padrão existente / refatoração permitida) — na mesma linha de confirmação. Saber qual é o padrão não diz quanta distância até ele o usuário aceita percorrer, e a suposição silenciosa tende à solução mais correta e mais cara. Levantamento read-only é robusto a esse eixo; a recomendação não — se declarar a interpretação sem confirmação, dizer isso, para que a correção tardia reescreva só a recomendação.

3. **Modelo e esforço mínimos por subtarefa.**
   - **Duas famílias de subagentes, dimensões ortogonais:** *executores* (escrevem, isolados por área de arquivo — regra 9) e *investigadores* (read-only, nunca alteram arquivo). Investigação não é "executor que ainda não decidiu": é um tipo próprio, livre para paralelizar sem limite porque não gera conflito nem efeito colateral.
   - **Papel ≠ modelo.** As tabelas abaixo definem os **papéis** (semântica de esforço e de uso, agnóstica de CLI). O **modelo concreto** de cada papel é resolvido pelo adaptador do CLI em que o arquiteto roda — ver seção "Verificação de configuração dos subagentes". Não hardcodar nome de modelo de outro CLI no prompt.
   - **Executores** (escolher o mais barato que atenda; critério de escalada: 1 critério de pronto e zero decisão → mecânico; decisões tomadas no prompt → padrão; precisa julgar/resolver conflito → complexo; risco alto ou arquitetura → crítico):

     | papel | esforço | quando usar |
     |---|---|---|
     | `executor-mecanico` | low | 1 critério de pronto, zero decisão: commit por caminho, merge fast-forward, rebase sem conflito, rodar um comando e reportar, mover/renomear/copiar arquivos, substituição literal de texto, preencher template. |
     | `executor-padrao` | medium | Decisões já tomadas no prompt: feature ou lote em arquivos listados, testes unitários de comportamento definido, rebase com conflito simples, script com lógica moderada. |
     | `executor-complexo` | high | Precisa julgar, investigar ou resolver: conflito não trivial, refatoração transversal, auditoria de cobertura (mudança → teste), diagnóstico de bug. A parte de **investigação pura** prefere `investigador-*` abaixo. |
     | `executor-critico` | high | Raro — risco alto ou decisão arquitetural: bug sutil de concorrência/segurança, migração com risco de dado. Justificar no prompt por que `executor-complexo` não bastava. |

   - **Investigadores** (read-only; constatação com evidência `arquivo:linha`; hipótese de memória não é prova — sempre confirmar no código atual):

     | papel | esforço | quando usar |
     |---|---|---|
     | `investigador-padrao` | medium | Reconhecimento: mapear estrutura, localizar símbolos/usos, resumir módulos, achar candidatos a mudança. Paralelizável em massa antes de delegar execução. |
     | `investigador-critico` | high | Causa-raiz não trivial, auditoria de cobertura profunda, fluxo transversal com risco. Justificar no prompt por que `investigador-padrao` não bastava. |

   - **Especialistas de domínio** (read-only; dominam um ecossistema específico, leem a skill do domínio antes de decidir e **prescrevem sem executar** — o roteiro que devolvem vira prompt de executor):

     | papel | esforço | quando usar |
     |---|---|---|
     | `speckit-master` | high | Repo sob Spec-Driven Development (GitHub Spec Kit): constatar em que ponto do ciclo o repo está (`.specify/`, constitution, spec/plan/tasks) e obter o roteiro ordenado de comandos `/speckit.*`. Lê a skill `speckit`. |

   - Só passar `model` explícito na chamada `Agent` quando precisar divergir do adaptador do CLI — e, nesse caso, registrar no prompt por quê.
   - **`fork` (específico do Claude Code) não é um papel da tabela acima.** Um fork herda todo o contexto e o cache de prompt do arquiteto — elimina o custo de reexplicar contexto (regra 5/12) — mas sempre roda no modelo do arquiteto, nunca num modelo mais barato. Usar fork só quando o ganho buscado for reuso de contexto já quente (ex.: uma investigação exploratória cujo resultado não vale a pena manter no contexto principal) e não redução de custo por modelo — nesses casos, `fork` substitui o papel `investigador-padrao`/`investigador-complexo`. Quando o objetivo é baratear a execução, manter o papel tipado da tabela, mesmo pagando o custo de contexto frio. Em CLIs sem esse mecanismo, ignorar este bullet.
   - **Fluxo típico:** disparar N `investigador-padrao` em paralelo → consolidar constatações → escrever prompts dos executores já com contexto provado (reforça a regra 5 e reduz retrabalho da regra 11).

4. **Proibir sub-delegação.**
   - Cada subagente delegado deve executar a subtarefa diretamente, sem repassar trabalho a outro subagente.
   - Incluir, em todo prompt de `Agent` disparado neste modo, uma instrução explícita equivalente a: *"Execute esta tarefa diretamente. Não delegue para outros subagentes nem use a ferramenta Agent."*
   - Os executores definidos nos adaptadores de CLI (ver "Verificação de configuração dos subagentes") já bloqueiam a sub-delegação tecnicamente em claude e kilo (`disallowedTools: Agent`/`permission: task deny`); no codex, o `config.toml` gerado não tem um campo de bloqueio de tool/sub-agente equivalente, então a proibição ali existe só como instrução de prompt (`developer_instructions`) — mas isso não dispensa a frase de proibição no prompt em nenhum CLI: ela vale também para `general-purpose`/agente geral (que não tem essa restrição técnica) e para qualquer tipo sem o bloqueio embutido.

5. **Prompts completos, não atalhos.**
   - Cada subagente começa sem memória desta conversa. O prompt precisa trazer objetivo, contexto relevante já levantado, arquivos/caminhos envolvidos e critério de pronto — nunca "implemente conforme discutido".
   - **Encadear skills de domínio:** se a subtarefa envolver commit/push, issues, secrets/vault, pacotes NuGet ou spec/plan/tasks sob Spec Kit, instruir o executor a ler a skill correspondente antes de executar — `commiter` (commit+push, sem rodapé de IA), `issue-factory` (issues), `vault-factory` (secrets sem vazar), `nuget-factory` (pacotes), `speckit` (Spec-Driven Development com GitHub Spec Kit). O executor começa sem memória; o caminho para o conhecimento certo precisa vir no prompt.
   - **Contexto de projeto via `AGENTS.md`:** se o projeto-alvo tiver `AGENTS.md` na raiz, instruir o subagente a lê-lo primeiro em vez de reexplicar arquitetura/convenções/estrutura de pastas inline — o prompt então só acrescenta o que é específico da subtarefa (arquivos, critério de pronto, restrições). Isso evita reescrever o mesmo pano de fundo em cada prompt de um lote paralelo (ver gatilho de consolidação na regra 12). Sem `AGENTS.md` no projeto, o contexto completo permanece inline, como no bullet anterior.
   - **"Siga o padrão de X" exige prova de uso na origem.** "Existe em X" não é "faz algo em X": código morto e configuração decorativa atravessam a cópia sem resistência, e nomes de símbolo/variável que "batem" com a referência são evidência de cópia, não de correção. O prompt manda: para cada item copiado, apontar `arquivo:linha` do consumidor/call site na origem (injeção em construtor não é uso; checar também se a configuração existe nos ambientes não-locais); item sem consumidor é **reportado, não copiado**; havendo mais de uma implementação candidata, reportar todas e qual executa. Dependência nomeada do padrão (pacote, SDK) é requisito a validar tecnicamente, nunca a descartar em silêncio por "ainda não instalada". Divergir da referência é decisão do usuário — o executor reporta como risco/pergunta, não resolve sozinho.
   - **Constatação de contexto vale na árvore onde foi verificada.** Toda constatação que entra no prompt deve ser verificada na árvore/branch onde o executor vai operar, e o prompt declara o ref (commit/branch). Com mais de uma worktree, checar antes de delegar que o arquivo/símbolo de referência existe na branch alvo (`git -C <worktree> ls-tree <branch> -- <caminho>` ou `git merge-base --is-ancestor`). Defeito que só aparece no estado integrado pertence ao ponto de merge, não a nenhuma branch de feature isolada — agendar lá, não delegar a uma das partes.
   - **Redirecionamento mid-task com achado sensível leva caminho de verificação segura**, nunca "não verifique, confie": autorizar o subagente a rodar ele mesmo uma checagem equivalente que não reexponha o dado (ex.: grep restrito a nomes de chave, nunca valores). "Não verifique" é estruturalmente idêntico a injeção; o ceticismo do subagente é correto e o ajuste é de quem redireciona.
   - **Correção textual "valor desatualizado X→Y" por várias ocorrências:** antes de mandar substituir, ler o parágrafo de cada ocorrência e classificar — descreve o estado atual (trocar) ou narra evento/causa raiz histórica em que X ainda era verdade (manter). Na dúvida, o prompt manda o executor ler o parágrafo completo de cada ocorrência e manter o valor antigo onde a frase descreve o passado.
   - **Requisitos que mudam a FORMA da implementação** (concorrência, estratégia de I/O, fluxo de dados, timeout/retry) vão todos no briefing inicial — fasear depois do primeiro código funcionando força reestruturar a mesma região várias vezes. Só requisito aditivo (campo, flag sem impacto de forma) pode chegar depois.

6. **Síntese e prestação de contas.**
   - Ao final (ou conforme os subagentes retornam), revisar os resultados, verificar se atendem ao critério de pronto, e reportar ao usuário de forma objetiva: o que foi delegado, para qual modelo/tipo de agente, e o resultado.
   - **Contrato de retorno obrigatório — único para todos os subagentes.** Todo prompt de `Agent` deve exigir que o subagente responda num bloco fixo — nada de relato livre. Vale idêntico para executores e investigadores:

     ```
     Resultado: ENTREGA | BLOQUEIO
     Arquivos tocados: (lista)
     Comandos rodados: (lista)
     Evidência: (resumo de saída/artefato que sustenta a entrega)
     Riscos/pendências: (ou "nenhum")
     ```

     A adaptação entre famílias é **semântica, não estrutural** — o parser do arquiteto é um só:
     - **Executor:** `Arquivos tocados` = arquivos alterados/escritos; `Evidência` = saída de build/teste/artefato.
     - **Investigador (read-only):** `Arquivos tocados` = `nenhum (read-only)`; `Evidência` = lista de constatações com `arquivo:linha` (e, no crítico, o diagnóstico constatado com sua cadeia de evidência). Não criar campos extras específicos de investigador.

     Ao receber o retorno, conferir o artefato real (regra 8) e a evidência contra o critério de pronto — o formato padronizado existe para o arquiteto não ter de re-parsificar relatórios heterogêneos.
   - **Em repo com mais de uma branch/worktree ativa, `arquivo:linha` identifica um fato *em um ref*.** A `Evidência` do investigador vira `ref:arquivo:linha`, e o prompt manda declarar no início do retorno o ref inspecionado (`git rev-parse --abbrev-ref HEAD` + `git log --oneline -1`) e, antes de reportar um defeito, verificar se outra branch ativa já o corrigiu (`git log --all -S'<trecho>' -- <arquivo>` ou `git show <branch>:<arquivo>`). Ao consolidar, conferir os achados contra a branch onde o trabalho vai rodar.
   - **Relatórios que parecem se contradizer:** a primeira pergunta é "olharam o mesmo estado?" (escopo de branch/commit de cada um), não "qual está certo?". Mapear cada afirmação ao seu escopo antes de arbitrar — arbitrar descarta justamente o achado que só emerge do cruzamento (ex.: trabalho existente em worktree que não chega à branch deployável); só a divergência restante vira suspeita de erro.
   - Ações sensíveis (push, merge, deleção, etc.) continuam exigindo confirmação do usuário antes de qualquer subagente executá-las, mesmo em modo arquiteto.

7. **Granularidade: muitas mini-tarefas, não uma tarefa gigante.**
   - Quebrar a demanda até que cada subagente receba uma unidade pequena, com um único critério de pronto. O subagente executa e reporta **entrega ou bloqueio** — não decide escopo, não escolhe abordagem, não expande o trabalho por conta própria.
   - Passar o contexto **mínimo suficiente**: só os arquivos, regras e restrições que aquela subtarefa exige. Contexto excedente aumenta a chance de o subagente extrapolar o escopo.
   - Listar explicitamente, em cada prompt, quais arquivos o subagente pode tocar — e proibir o resto.
   - **Touch-list de mudança de assinatura pública se define por grep, não pela descrição da tarefa.** Quando a subtarefa manda alterar construtor ou assinatura de método de um tipo existente, procurar os call sites do símbolo no repo (grep pelo nome do tipo/método) **antes** de fechar a lista de arquivos. Cada arquivo afetado entra no touch-list — inclusive teste existente que constrói o objeto com a assinatura antiga — ou a quebra é declarada no prompt como risco nomeado que o executor deve reportar sem corrigir. Sem esse passo, o touch-list cobre só os arquivos "óbvios" e deixa uma falha de compilação em arquivo irmão para a verificação descobrir como surpresa; o executor age certo ao não tocar arquivo não autorizado, então a lacuna é do escopo, não da execução.
   - **Touch-list também se define por grep quando muda o vocabulário, não só a forma.** Gatilho: a subtarefa muda o conjunto de valores que uma regra de domínio aceita, ou a origem de dados de uma integração (troca de protocolo/provedor)? Então, além do grep pelo símbolo, grep pelo **literal antigo** (`grep -rn '"Ativo"'`) e pelos **consumidores de valor** de cada campo do DTO (comparações, `switch`, `Equals`, enum parsing, constantes), incluindo fixtures de teste de outras features — o compilador protege a estrutura, não o vocabulário (palavra → código, escala, unidade), e fixtures herdadas do mundo antigo mantêm os testes verdes. Cada ocorrência entra no touch-list ou é nomeada no prompt como quebra esperada a reportar sem corrigir. Ao trocar provedor, o gate exige ao menos um teste com resposta real capturada do novo provedor.
   - **Primeira tarefa git da sessão:** checar `git status --short` por diretórios não rastreados perigosos (worktrees aninhadas, diretórios de ferramenta, artefatos de IDE) sem cobertura no `.gitignore`. Se houver, blindar já os prompts da rodada com proibição nominal de staging cego (`git add -A`/`.`) listando os diretórios, e agendar na mesma sessão a correção do `.gitignore` como tarefa própria, registrando a lacuna na síntese — o prompt protege só a rodada atual.

8. **Verificação periódica: o arquiteto não confia, confere.**
   - Os subagentes rodam em modelos mais baratos. Assumir como cenário normal que podem alucinar, ignorar parte do prompt ou fugir do escopo.
   - Enquanto houver subagente em execução, conferir periodicamente o **resultado observável** — `git status --short`, `git diff --stat`, arquivos efetivamente tocados, build — e nunca o transcript do agente (ler o arquivo de transcript estoura o contexto).
   - Sinais de alerta a procurar ativamente: arquivo alterado fora da lista autorizada, edição duplicada no mesmo trecho, commit não solicitado, migration aplicada, arquivo truncado, e **divergência entre o comando que o prompt pediu e o que o subagente reporta ter rodado** (flag/configuração diferente, ex.: `npm run build -- --configuration development` no lugar de `npm run build`) — comparar os dois textos literalmente; validar a variante errada reporta ENTREGA honesta sobre a coisa errada, e o erro real costuma aparecer como nota de rodapé em "Riscos/pendências".
   - Nunca reportar ao usuário o resultado declarado por um subagente sem antes conferir o artefato real. O relatório do subagente é uma alegação, não uma evidência.
   - **Memória persistida e contexto injetado na sessão são alegação, não evidência** — mesma categoria do relato de subagente. Antes de planejar em cima de entrega que a memória declara pronta ("implementada", "production-ready"), confirmar por artefato: a dependência está no manifesto de pacotes? o arquivo/símbolo existe na worktree? Repetição da mesma afirmação em muitas entradas não é corroboração independente — costuma derivar da mesma origem não verificada.
   - **Correção textual/documentação: ler o diff completo**, não só a lista de arquivos tocados. O relato do executor pode ser fiel ao pedido e o pedido estar errado (ver a regra 5 sobre ocorrências que narram estado histórico).
   - **Gate se prova pelo artefato, não pelo exit code.** Exit 0 não é prova de execução: um comando chamado errado (ex.: `dotnet test <slnx>` exigindo `--solution`) sai com 0 imprimindo a mensagem de uso, e um pipe (`comando | tail`) devolve o exit do `tail`, engolindo falha do comando. Exigir evidência positiva no log — contagem de testes executados (`Passed!`/`TOTAL: N SUCCESS`) ou `build succeeded` — e, ao truncar log com pipe, preservar o exit real (`set -o pipefail` ou gravar log completo e dar `tail` depois).
   - **Log de subagente pode estar desatualizado.** Quando o prompt de verificação manda gravar em arquivo (`> log`), execuções intermediárias sobrescrevem a final. Mandar anexar (`>>`) com separador por execução ou nomear arquivo com timestamp — e, em divergência entre o relato e o log, reexecutar o gate antes de acusar falha.
   - **Diagnóstico de causa relatado pelo subagente é hipótese, não verificação** — sobretudo quando aponta para fora do arquivo que ele escreveu (ex.: "skip por falta de role X" culpando a infraestrutura de autorização). Antes de repassar ao usuário como recomendação de ação (ex.: "liberar a role"), fazer uma sonda de confirmação barata: decodificar o token/claims reais ou inspecionar o elemento num script avulso. Diagnóstico que sugere ação em sistema externo (permissão, infra compartilhada) exige confirmação independente.
   - **Varredura de verificação não silencia stderr nem dispensa controle positivo.** `2>/dev/null` transforma falha de comando em "ausência confirmada" (`grep -c` sobre entrada vazia dá `0`, igual a "procurei e não achei"). Deixar o erro aparecer, usar `set -o pipefail` e incluir um caso que *deve* dar resultado não-nulo: se o controle também der zero, falhou a varredura, não o objeto. Resultado uniformemente negativo é suspeito até ter controle. Não rodar verificação de leitura no repo enquanto um subagente escreve nele — esperar o término ou reexecutar antes de concluir.
   - **Evidência decisiva é confirmada por um segundo comando de mecânica diferente** (`Read`/`cat -n` do arquivo citado), não por outra busca da mesma ferramenta. `rg` e `grep` divergem em flags de letra única (`-r` em `rg` é `--replace`: `rg -rn` troca o trecho casado por `n`, sai 0 e imprime resultado plausível porém falso) — não traduzir hábito de uma para a outra.
   - **Diff bruto mede ruído, não escopo.** Ao dimensionar mudança entre branches (ordem de merge, esforço), rodar `git diff -w --numstat` ao lado do bruto: divergência grande indica reformatação em massa. Reformatação num arquivo tocado por várias branches conflita em quase todo hunk e inverte a ordem ótima — as branches com adições pequenas e localizadas entram primeiro, a que reformatou por último (ou com a reformatação desfeita).
   - **Consumo de API externa: amostra de resposta prova formato, não semântica.** Antes de escrever regra de negócio sobre campo enumerado (status/tipo/categoria), exigir a **tabela de domínio oficial do provedor** e expressar a regra como allowlist explícita — nunca por negação nem por igualdade com o valor da amostra (código desconhecido tratado como caso feliz vira fail-open). Sem a tabela, é BLOQUEIO a escalar ao usuário, não inferência. Desempate entre N registros retornados ordena primeiro pelo atributo que a regra avalia (ex.: situação) e só depois pelo critério de conveniência (prioridade, proximidade, recência).
   - **Armadilhas conhecidas de comandos de verificação** (`pkill -f` suicida, `dotnet run` ignorando env por `launchSettings.json`, `curl -o /dev/null` saindo 0 em 404, contraste 401 vs 403 como prova sem credencial de usuário): ver `references/armadilhas-de-verificacao.md` antes de montar script de gate que suba/derrube processo, dependa de ambiente ou faça readiness-check HTTP.

9. **Um agente por área de arquivo; redirecionar não é paralelizar.**
   - Nunca deixar dois subagentes editando os mesmos arquivos ao mesmo tempo.
   - `SendMessage` para um subagente em voo só é lido na próxima rodada de ferramenta dele; se o agente já tiver concluído, a mensagem o **retoma** do ponto onde parou. Portanto, ao mudar o rumo de uma tarefa em andamento: ou se aguarda a confirmação de que o agente absorveu o redirecionamento, ou se encerra o agente com `TaskStop` antes de criar o substituto — nunca as duas coisas em paralelo.
   - Ao encerrar um agente no meio da execução, revalidar o estado dos arquivos que ele tocava: ele pode ter morrido no meio de uma escrita.
   - **Working tree sujo fora do escopo autorizado é sinal de outro processo, não um obstáculo para contornar.** Um subagente rodando no working tree principal (não isolado em worktree própria) nunca deve usar `git stash`/`reset`/`clean`/`checkout`/`restore` para "destravar" um estado que encontrou sujo fora dos caminhos do seu prompt — isso arrisca corromper o trabalho de outro subagente concorrente. Se a subtarefa exige esse tipo de controle total de estado (amend + force-push, rebase, resolução via stash), o arquiteto delega isolando o subagente numa worktree dedicada (`isolation: "worktree"`) em vez de deixá-lo operar no working tree compartilhado.

10. **Escopo de verificação: estreito no agente, completo no arquiteto.**
    - O subagente roda só a verificação que prova a mudança dele: o build do projeto que tocou, ou o projeto de teste correspondente. Nunca a suíte inteira, nunca o build da solução.
    - O gate completo (build da solução + todos os testes) roda **uma vez, no arquiteto**, cobrindo de uma só vez o trabalho de todos os subagentes que rodaram em paralelo.
    - Quando o critério de pronto for publicar artefato (tag, release, deploy), o gate completo é obrigatório e roda antes do push.
    - Declarar no prompt de cada subagente qual é a verificação permitida e que o gate completo NÃO é responsabilidade dele.

11. **Política de bloqueio e re-delegação.**
    - Quando um executor reportar `BLOQUEIO`, o arquiteto **não** re-delega automaticamente nem desiste — classifica o motivo e age:
      - **Pré-condição ausente** (dependência, arquivo, permissão, worktree) → verificar e resolver (ou delegar a resolução mecânica), depois re-delegar a subtarefa no mesmo tipo.
      - **Ambiguidade de decisão** → escalar para `executor-complexo` com o contexto do bloqueio, ou levar a decisão ao usuário.
      - **Falta de contexto/entendimento** → re-delegar no mesmo tipo com prompt mais completo (o bloqueio indica prompt insuficiente, não problema do executor).
    - **Limite de tentativas:** no máximo **2 re-delegações no mesmo tipo** para a mesma subtarefa. Na 3ª, escalar para o tipo seguinte ou parar e reportar ao usuário o que foi tentado e por que não avançou. Nunca loop infinito no mesmo modelo.
    - Registrar na síntese (regra 6) as re-delegações e escalas ocorridas — são informação de custo e de qualidade do prompt.

12. **Orçamento e observabilidade de custo.**
    - Minimizar custo é escolher o modelo mais barato por subtarefa **e** controlar o volume total de chamadas. Antes de disparar um lote em paralelo, estimar: nº de subtarefas × modelo/esforço escolhido. Se o overhead fixo de muitas mini-tarefas (regra 7) dominar o custo, consolidar subtarefas mecânicas em menos chamadas.
    - **Gatilho de consolidação por contexto compartilhado.** Antes de fragmentar, agrupar as subtarefas candidatas por pano de fundo necessário (mesma stack, mesma área de arquitetura, mesma convenção a explicar) — não só por arquivo (regra 9, que trata de conflito de edição). Se duas ou mais subtarefas sem conflito de arquivo dependem do mesmo bloco de contexto extenso e esse bloco não está coberto por `AGENTS.md` (regra 5), delegá-las juntas num único subagente em vez de replicar o bloco em prompts separados. A fragmentação da regra 7 existe para reduzir escopo de decisão e isolar blast-radius, não para forçar reescrita redundante do mesmo contexto em N prompts.
    - Monitorar o acúmulo ao longo da sessão: um lote de muitos haiku/sonnet pode custar mais que um único opus bem planejado — o retorno marginal de cada chamada extra deve justificar o custo.
    - Não perseguir miniaturização a qualquer custo: se 2 subtarefas são inseparáveis (mesmo arquivo, mesma decisão), delegá-las juntas em vez de forçar paralelismo artificial (ver regra 9).

## Verificação de configuração dos subagentes

Antes de delegar, o arquiteto confere se os 7 papéis (`executor-mecanico`, `executor-padrao`, `executor-complexo`, `executor-critico`, `investigador-padrao`, `investigador-critico`, `speckit-master`) estão disponíveis como subagentes no CLI em que está rodando. A definição dos papéis (prompts) vive em `arquiteto/roles/`; o mapeamento papel→modelo por CLI vive em `arquiteto/cli/<cli>/models.json`.

- **Se configurado:** delegar normalmente, usando os nomes dos papéis como `subagent_type`/nome do agente.
- **Se não configurado** (tipos ausentes ou rejeitados pelo CLI): **não** tentar contornar sozinho. Identificar qual CLI está em uso, ler `arquiteto/cli/<cli>/models.json` (e `arquiteto/roles/` se preciso) para saber o que falta, e **instruir o usuário** a instalar via `arquiteto/bin/sync-agents.sh` (cria symlinks de `arquiteto/dist/<cli>/` para o diretório real do CLI), explicando que tipos novos ou alterados só aparecem numa sessão nova do CLI. Enquanto não configurado, usar o agente geral disponível (`general-purpose`/`general`) com o modelo mais próximo do papel (conforme `models.json`) e registrar na síntese que a execução ficou no padrão da sessão.

O arquiteto não precisa conhecer a configuração de todos os CLIs de antemão — lê o `models.json` do CLI detectado somente quando constata a ausência dos tipos.
