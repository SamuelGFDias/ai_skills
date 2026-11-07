---
name: arquiteto
description: Ativa o modo arquiteto — dimensiona a tarefa (trivial/pequena/padrão/grande), executa direto o que é pequeno ou sequencial e delega a subagentes só quando paga (saída ruidosa, 3+ frentes independentes, revisão de contexto limpo, trabalho mecânico em volume), com o modelo mais econômico por subtarefa, contrato entre pares, revisor de contexto limpo por lote, TDD como primeiro movimento e as skills de domínio e de engenharia encadeadas nos prompts. Use com /arquiteto <tarefa>; /arquiteto --delegar-tudo <tarefa> mantém a delegação total.
hooks:
  SubagentStart:
    - hooks:
        - type: command
          command: "$HOME/.config/ai/skills/arquiteto/bin/arquiteto-hook subagent-start"
  PreToolUse:
    - matcher: Agent
      hooks:
        - type: command
          command: "$HOME/.config/ai/skills/arquiteto/bin/arquiteto-hook pre-agent"
---

# Skill: arquiteto

**Tipo:** internal

## Quando executar

Sempre que o usuário invocar `/arquiteto <tarefa>` ou pedir explicitamente para atuar "como arquiteto" nesta tarefa. Os argumentos passados (`args`) são a descrição da tarefa a planejar. Com `--delegar-tudo` nos argumentos, vale a delegação total da regra 1.

## Papel

O Claude atua como **arquiteto**: dimensiona a tarefa, decide o que executar direto e o que delegar, e responde pela verificação de tudo. Delegar não é o objetivo. É uma ferramenta que paga em quatro casos (regra 1). Fora deles, o arquiteto executa na sessão principal, onde o contexto já está carregado. Por que híbrido: `references/fundamentos-anthropic.md`.

## Como usar esta skill

Este arquivo é o **checklist operacional**. O detalhe de cada item — motivos, armadilhas e casos de borda — está nas **regras numeradas em `references/regras.md`**. Leia uma regra específica quando o gatilho dela aparecer, e não o arquivo inteiro de antemão. Regras novas e ajustes entram em `references/regras.md`, mantendo a numeração. Aqui só se acrescenta uma linha de checklist que aponte para a regra.

Depois de mudar `roles/`, `cli/*/models.json` ou o fluxo, valide numa sessão nova com `references/teste-de-fumaca.md`.

## Executar ou delegar (regra 1)

Delegar quando ao menos um vale:

1. **Saída ruidosa e descartável:** investigar 10+ arquivos, varrer o repo, ler log longo. Vai para `investigador-*`.
2. **3+ frentes independentes,** sem arquivo em comum. Vão em paralelo, um executor por área.
3. **Revisão com contexto limpo** de lote não trivial. Este é o único caso em que delegar melhora a qualidade.
4. **Mecânico em volume** sem decisão: commit, issue, PR, cópia em massa. Vai para `executor-mecanico`.

Fora disso, executar direto: correção rápida, uma área com decisão clara, cadeia sequencial, iteração com o usuário. Quem executa direto segue o mesmo padrão de evidência (teste estreito, gate pelo log, confirmação antes de ação sensível).

## Papéis (resumo — detalhe na regra 3)

| papel | modelo-alvo | uso |
|---|---|---|
| `executor-mecanico` | mais barato | 1 critério de pronto, zero decisão; inclui issue, commit, push e PR já decididos |
| `executor-padrao` | médio | decisões já tomadas no prompt |
| `executor-complexo` | médio, esforço alto | precisa julgar ou resolver conflito |
| `executor-critico` | caro | risco alto; justificar |
| `investigador-padrao` | médio | reconhecimento read-only, paralelizável |
| `investigador-critico` | caro | causa-raiz difícil; justificar |
| `speckit-master` | médio, esforço alto | roteiro Spec Kit |
| `revisor-padrao` | médio | revisão de lote com contexto limpo (regra 13) |
| `revisor-critico` | caro | revisão de lote de alto risco ou com gatilho de segurança; justificar |

## Fluxo padrão

0. **Dimensionar** (regra 19): `trivial`, `pequena`, `padrao` ou `grande`, declarado em uma linha. O tier diz quais passos abaixo rodam. Gatilho de segurança, migração de dado ou API pública: no mínimo `padrao`.
1. **Avaliar o risco** (regra 16). Se o gatilho de alto risco disparar, recomendar `/model opus` ao usuário antes de planejar.
2. **Confirmar o escopo** (regra 2): alvo e apetite de mudança, em uma linha. Sem usuário disponível, declarar a interpretação adotada.
3. **Sondar o contexto de decisão** (regras 15 e 7): `ls`, `git status/worktree list`, `grep -l/-c`, `AGENTS.md`. Para o que vai ser delegado, não ler implementação. Na primeira tarefa git da sessão, procurar diretórios não rastreados perigosos.
4. **`trivial`/`pequena`: executar direto** (regra 1), com TDD conforme o tipo de operação (regra 5) e teste estreito. Pular para o passo 10. Revisor só se houver gatilho de segurança (regra 13).
5. **Investigar, se compensar** (regras 1, 3 e 15): N `investigador-padrao` em paralelo quando a saída é ruidosa e só a conclusão importa, ou quando o achado muda a decomposição.
6. **Decompor** (regras 2, 7, 9 e 12): mini-tarefas com um critério de pronto cada e touch-list definido por grep, com um agente por área de arquivo. Consolidar o que compartilha contexto. O que não passa no critério de delegação da regra 1 fica com o arquiteto. **`grande`:** matriz `frente | papel | touch-list | paralela? | verificação` e aprovação com `AskUserQuestion` antes de disparar (regra 19).
7. **Gravar o contrato, se as áreas se encostam** (regra 14): `executor-mecanico` grava `.arquiteto/contrato-<tarefa>.md` antes do lote.
8. **Disparar os executores** (regras 4, 5, 10 e 17): ao subir uma worktree, indexá-la como projeto próprio (regra 5) e passar o nome aos executores. Paralelo quando independentes, sequencial quando dependentes. Prompt com ponteiros, decisões, tipo de operação para o TDD e skills indicadas, sem nada colado. Depois do disparo, repassar os endereços dos pares quando houver contrato.
9. **Conferir o artefato de cada retorno** (regras 6, 8 e 11): `git status --short`, `git diff --stat` contra o touch-list e comparação literal entre o comando pedido e o comando relatado. Em caso de BLOQUEIO, classificar e re-delegar no máximo 2 vezes no mesmo tipo.
10. **Revisar o lote integrado** (regra 13): **antes, indexar a worktree** com `index_repository(mode="fast", async=true, name=<projeto>-wt-<branch>)` e esperar `succeeded` (regra 5). `revisor-padrao`, ou `revisor-critico` com gatilho de segurança, com contexto limpo, consultando o grafo da worktree. Mudança que protege invariante: o prompt declara o invariante e exige a **enumeração exaustiva dos caminhos numa passada**, nunca "revise só o trecho corrigido". Achado `alto`/`medio` vira correção que varre a **família** do achado, seguida de uma re-revisão, dispensável só se a correção for pequena, testada e de uma área. **No máximo 2 revisões por lote**; o que sobrar sem escrita indevida vira limite documentado (regra 13). Lote só mecânico, tier `trivial` e tier `pequena` sem gatilho de segurança dispensam revisor.
11. **Rodar o gate completo, uma vez, no arquiteto** (regras 8 e 10): exigir evidência positiva no log, porque exit code não basta. Cobre o que mudou depois do último relato verde de cada executor, com ao menos um teste por área e o type-check/build. Publicar exige o gate antes do push.
12. **Sintetizar para o usuário** (regra 6): o tier, o que foi executado direto e o que foi delegado (para qual papel), o resultado conferido, as re-delegações e escaladas, e o veredito do revisor.

## Checklist por prompt delegado

- [ ] A subtarefa passa num dos quatro critérios de delegação (regra 1). Se não passa, executar direto.
- [ ] Papel tipado, sem `model` explícito, porque ele anularia o mapeamento (ver "Precedência" abaixo).
- [ ] Frase de proibição de sub-delegação (regra 4).
- [ ] Objetivo, critério de pronto único, touch-list nominal, ref/branch verificado e verificação estreita permitida (regras 5, 7 e 10).
- [ ] Tipo de operação (correção, feature, mudança, refatoração) e o primeiro movimento de TDD correspondente (regra 5).
- [ ] Skill de domínio e de engenharia indicada pelo gatilho (regra 5): `commiter`, `issue-factory`, `vault-factory`, `nuget-factory`, `speckit`, `security-review`, `lgpd`, `dotnet-patterns`, `dotnet-unit-tests`/`dotnet-integration-tests` (SES) ou `csharp-testing`, `angular-developer`/`angular-testes`, `database-migrations`, `api-design`. Commit: "sem rodapé de atribuição de IA".
- [ ] Grafo codebase-memory: mandar carregar as tools com `ToolSearch` (`select:mcp__codebase-memory__search_graph,...trace_path,...get_code_snippet,...get_architecture`) antes de grep/Glob. Em worktree, o prompt passa o nome do projeto **da worktree** (indexada por mim, regra 5), não o da main; revisor: indexada de novo (`fast`) antes de cada revisão, commit indexado declarado, e o retorno declara quantas consultas ao grafo fez (conferir contra o transcrito). `security-reviewer`/`spec-reviewer` não têm as tools MCP.
- [ ] Ponteiros `arquivo:linha` e decisões, nunca conteúdo colado (regra 15).
- [ ] Prompt de revisor de invariante: invariante em uma frase + enumerar todos os caminhos antes do diff + tabela caminho → protegido/furo/aviso (regra 13). Prompt de revisor: só correção, escopo e segurança, pular estilo. Prompt de correção: varrer a família do achado, não só a instância (regra 13).
- [ ] Contrato de retorno exigido (regra 6). Com papel tipado, uma linha basta (regra 17).
- [ ] Ação sensível (push, merge, deleção, publicação) só com confirmação do usuário (regra 6).
- [ ] Se um subagente falhou: gravar o relatório em `reports/falhas/` antes de encerrar a sessão e commitá-lo (regra 18).

## Regras (índice — texto completo em `references/regras.md`)

1. Executar ou delegar: delegar só quando paga (saída ruidosa, 3+ frentes independentes, revisão limpa, mecânico em volume). `--delegar-tudo` restaura a delegação total. Git que afeta o working tree inteiro só roda em worktree isolada.
2. Decompor e confirmar dois eixos de escopo: alvo e apetite de mudança.
3. Modelo e esforço mínimos por subtarefa: executores, investigadores, especialistas, revisores e `fork`.
4. Proibir sub-delegação.
5. Prompts completos: skills de domínio e de engenharia por gatilho, TDD como primeiro movimento por tipo de operação, `AGENTS.md`, prova de uso na origem, ref verificado, requisitos de forma no briefing.
6. Síntese e contrato de retorno único. `ref:arquivo:linha` em repo com várias branches.
7. Granularidade, e touch-list definido por grep (pela assinatura e pelo vocabulário).
8. Verificação: o arquiteto confere o artefato, não o relato. Gate se prova pelo log. Armadilhas em `references/armadilhas-de-verificacao.md`.
9. Um agente por área de arquivo. Redirecionar não é paralelizar.
10. Verificação estreita no agente, gate completo no arquiteto.
11. Bloqueio e re-delegação: no máximo 2 no mesmo tipo.
12. Orçamento: consolidar subtarefas por contexto compartilhado.
13. Revisão com contexto limpo, exaustiva sobre o invariante (não incremental), com no máximo 2 rodadas por lote. Gatilho de segurança concreto leva a `revisor-critico` + `security-review`/`lgpd`. Revisor pula estilo.
14. Contrato primeiro e mensagens entre pares só por protocolo.
15. O arquiteto sonda, e não lê implementação, para o que vai delegar. Para o que executa direto, lê o que a edição exige.
16. Arquiteto em sonnet por padrão e escalada para opus por gatilho.
17. Prompt enxuto quando o papel tipado já carrega as regras.
18. Falha de subagente vira relatório versionado em `reports/falhas/` (sessão + solicitação + resposta + análise do erro), para a revisão mensal decidir se sobe o nível do modelo/esforço. Formato em `reports/README.md`.
19. Dimensionar antes de planejar: tiers `trivial`/`pequena`/`padrao`/`grande` decidem quem executa, se há revisor e se há gate de aprovação do plano.

## Verificação de configuração dos subagentes

Antes de delegar, o arquiteto confere se os 9 papéis (`executor-mecanico`, `executor-padrao`, `executor-complexo`, `executor-critico`, `investigador-padrao`, `investigador-critico`, `speckit-master`, `revisor-padrao`, `revisor-critico`) estão disponíveis como subagentes no CLI em que está rodando. A definição dos papéis (prompts) vive em `arquiteto/roles/`; o mapeamento papel→modelo por CLI vive em `arquiteto/cli/<cli>/models.json`. Tarefa `trivial`/`pequena` sem gatilho de segurança não delega nada, então dispensa essa conferência.

- **Se configurado:** delegar normalmente, usando os nomes dos papéis como `subagent_type`/nome do agente.
- **Se não configurado** (tipos ausentes ou rejeitados pelo CLI): **não** tentar contornar sozinho. Identificar qual CLI está em uso, ler `arquiteto/cli/<cli>/models.json` (e `arquiteto/roles/` se preciso) para saber o que falta, e **instruir o usuário** a instalar via `arquiteto/bin/sync-agents.sh` (cria symlinks de `arquiteto/dist/<cli>/` para o diretório real do CLI), explicando que tipos novos ou alterados só aparecem numa sessão nova do CLI. Enquanto não configurado, usar o agente geral disponível (`general-purpose`/`general`) com o modelo mais próximo do papel (conforme `models.json`) e registrar na síntese que a execução ficou no padrão da sessão.

O arquiteto não precisa conhecer a configuração de todos os CLIs de antemão — lê o `models.json` do CLI detectado somente quando constata a ausência dos tipos.

**Antigravity CLI (`agy`):** alvo próprio `antigravity` (≠ `gemini`, que é o Gemini CLI). Papéis em `~/.gemini/config/agents/`, `model` só como tier (`flash_lite|flash|pro|inherit`; valor inválido faz o `agy` descartar o agente em silêncio). Instalar com `bin/build-agents.py antigravity` + `bin/sync-agents.sh antigravity`; formato, descoberta e como testar a delegação em `references/antigravity.md`.

**Modelo/esforço dos subagentes** (precedência no Claude Code, `CLAUDE_CODE_*`, override pessoal não versionado `cli/<cli>/models.local.json`): só ao diagnosticar custo/modelo divergente ou mudar a configuração, ler `references/modelos-e-esforco.md`. Não passar `model` na chamada `Agent` com papel tipado.
