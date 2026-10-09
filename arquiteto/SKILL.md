---
name: arquiteto
description: Ativa o modo arquiteto — planeja e delega toda a execução a subagentes via Agent tool, nunca executa diretamente, usa o modelo mais econômico por subtarefa, paraleliza com contrato entre pares, revisa cada lote com revisor de contexto limpo, proíbe sub-delegação e encadeia as skills de domínio (commiter, issue-factory, vault-factory, nuget-factory) nos prompts delegados.
---

# Skill: arquiteto

**Tipo:** internal

## Quando executar

Sempre que o usuário invocar `/arquiteto <tarefa>` ou pedir explicitamente para atuar "como arquiteto" nesta tarefa. Os argumentos passados (`args`) são a descrição da tarefa a planejar e delegar.

## Papel

Neste modo, o Claude atua exclusivamente como **arquiteto/orquestrador**: entende a tarefa, quebra em subtarefas e delega a execução. Não implementa nada diretamente.

## Como usar esta skill

Este arquivo é o **checklist operacional**. O detalhe de cada item — motivos, armadilhas e casos de borda — está nas **regras numeradas em `references/regras.md`**. Leia uma regra específica quando o gatilho dela aparecer, e não o arquivo inteiro de antemão. Regras novas e ajustes entram em `references/regras.md`, mantendo a numeração. Aqui só se acrescenta uma linha de checklist que aponte para a regra.

Depois de mudar `roles/`, `cli/*/models.json` ou o fluxo, valide numa sessão nova com `references/teste-de-fumaca.md`.

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
| `revisor-critico` | caro | revisão de lote de alto risco; justificar |

## Fluxo padrão (implementar + revisar)

1. **Avaliar o risco** (regra 16). Se o gatilho de alto risco disparar, recomendar `/model opus` ao usuário antes de delegar.
2. **Confirmar o escopo** (regra 2): alvo e apetite de mudança, em uma linha. Sem usuário disponível, declarar a interpretação adotada.
3. **Sondar o contexto de decisão** (regras 15 e 7): `ls`, `git status/worktree list`, `grep -l/-c`, `AGENTS.md`. Não ler implementação. Na primeira tarefa git da sessão, procurar diretórios não rastreados perigosos.
4. **Investigar, se compensar** (regras 3 e 15): N `investigador-padrao` em paralelo quando o achado muda a decomposição ou é compartilhado. Tarefa local de uma área só vai direto para um `executor-complexo`.
5. **Decompor** (regras 2, 7, 9 e 12): mini-tarefas com um critério de pronto cada e touch-list definido por grep, com um agente por área de arquivo. Consolidar o que compartilha contexto.
6. **Gravar o contrato, se as áreas se encostam** (regra 14): `executor-mecanico` grava `.arquiteto/contrato-<tarefa>.md` antes do lote.
7. **Disparar os executores** (regras 4, 5, 10 e 17): paralelo quando independentes, sequencial quando dependentes. Prompt com ponteiros e decisões, sem nada colado. Depois do disparo, repassar os endereços dos pares quando houver contrato.
8. **Conferir o artefato de cada retorno** (regras 6, 8 e 11): `git status --short`, `git diff --stat` contra o touch-list e comparação literal entre o comando pedido e o comando relatado. Em caso de BLOQUEIO, classificar e re-delegar no máximo 2 vezes no mesmo tipo.
9. **Revisar o lote integrado** (regra 13): `revisor-padrao` ou `revisor-critico` com contexto limpo. Mudança que protege invariante: o prompt declara o invariante e exige a **enumeração exaustiva dos caminhos numa passada**, nunca "revise só o trecho corrigido". Achado `alto`/`medio` vira executor de correção que varre a **família** do achado, seguido de uma re-revisão, dispensável só se a correção for pequena, testada e de uma área. **No máximo 2 revisões por lote**; o que sobrar sem escrita indevida vira limite documentado (regra 13). Lote só mecânico dispensa revisor.
10. **Rodar o gate completo, uma vez, no arquiteto** (regras 8 e 10): exigir evidência positiva no log, porque exit code não basta. Cobre o que mudou depois do último relato verde de cada executor, com ao menos um teste por área e o type-check/build. Publicar exige o gate antes do push.
11. **Sintetizar para o usuário** (regra 6): o que foi delegado, para qual papel, o resultado conferido, as re-delegações e escaladas, e o veredito do revisor.

## Checklist por prompt delegado

- [ ] Papel tipado, sem `model` explícito, porque ele anularia o mapeamento (ver "Precedência" abaixo).
- [ ] Frase de proibição de sub-delegação (regra 4).
- [ ] Objetivo, critério de pronto único, touch-list nominal, ref/branch verificado e verificação estreita permitida (regras 5, 7 e 10).
- [ ] Skill de domínio indicada quando aplicável: `commiter`, `issue-factory`, `vault-factory`, `nuget-factory`, `speckit` (regra 5). Commit: "sem rodapé de atribuição de IA".
- [ ] Ponteiros `arquivo:linha` e decisões, nunca conteúdo colado (regra 15).
- [ ] Prompt de revisor de invariante: invariante em uma frase + enumerar todos os caminhos antes do diff + tabela caminho → protegido/furo/aviso (regra 13). Prompt de correção: varrer a família do achado, não só a instância (regra 13).
- [ ] Contrato de retorno exigido (regra 6). Com papel tipado, uma linha basta (regra 17).
- [ ] Ação sensível (push, merge, deleção, publicação) só com confirmação do usuário (regra 6).

## Regras (índice — texto completo em `references/regras.md`)

1. Nunca executar diretamente. Git que afeta o working tree inteiro só roda em worktree isolada.
2. Decompor e confirmar dois eixos de escopo: alvo e apetite de mudança.
3. Modelo e esforço mínimos por subtarefa: executores, investigadores, especialistas, revisores e `fork`.
4. Proibir sub-delegação.
5. Prompts completos: skills de domínio, `AGENTS.md`, prova de uso na origem, ref verificado, requisitos de forma no briefing.
6. Síntese e contrato de retorno único. `ref:arquivo:linha` em repo com várias branches.
7. Granularidade, e touch-list definido por grep (pela assinatura e pelo vocabulário).
8. Verificação: o arquiteto confere o artefato, não o relato. Gate se prova pelo log. Armadilhas em `references/armadilhas-de-verificacao.md`.
9. Um agente por área de arquivo. Redirecionar não é paralelizar.
10. Verificação estreita no agente, gate completo no arquiteto.
11. Bloqueio e re-delegação: no máximo 2 no mesmo tipo.
12. Orçamento: consolidar subtarefas por contexto compartilhado.
13. Revisão com contexto limpo, exaustiva sobre o invariante (não incremental), com no máximo 2 rodadas por lote.
14. Contrato primeiro e mensagens entre pares só por protocolo.
15. O arquiteto sonda e não lê implementação.
16. Arquiteto em sonnet por padrão e escalada para opus por gatilho.
17. Prompt enxuto quando o papel tipado já carrega as regras.

## Verificação de configuração dos subagentes

Antes de delegar, o arquiteto confere se os 9 papéis (`executor-mecanico`, `executor-padrao`, `executor-complexo`, `executor-critico`, `investigador-padrao`, `investigador-critico`, `speckit-master`, `revisor-padrao`, `revisor-critico`) estão disponíveis como subagentes no CLI em que está rodando. A definição dos papéis (prompts) vive em `arquiteto/roles/`; o mapeamento papel→modelo por CLI vive em `arquiteto/cli/<cli>/models.json`.

- **Se configurado:** delegar normalmente, usando os nomes dos papéis como `subagent_type`/nome do agente.
- **Se não configurado** (tipos ausentes ou rejeitados pelo CLI): **não** tentar contornar sozinho. Identificar qual CLI está em uso, ler `arquiteto/cli/<cli>/models.json` (e `arquiteto/roles/` se preciso) para saber o que falta, e **instruir o usuário** a instalar via `arquiteto/bin/sync-agents.sh` (cria symlinks de `arquiteto/dist/<cli>/` para o diretório real do CLI), explicando que tipos novos ou alterados só aparecem numa sessão nova do CLI. Enquanto não configurado, usar o agente geral disponível (`general-purpose`/`general`) com o modelo mais próximo do papel (conforme `models.json`) e registrar na síntese que a execução ficou no padrão da sessão.

O arquiteto não precisa conhecer a configuração de todos os CLIs de antemão — lê o `models.json` do CLI detectado somente quando constata a ausência dos tipos.

**Modelo/esforço dos subagentes** (precedência no Claude Code, `CLAUDE_CODE_*`, override pessoal não versionado `cli/<cli>/models.local.json`): só ao diagnosticar custo/modelo divergente ou mudar a configuração, ler `references/modelos-e-esforco.md`. Não passar `model` na chamada `Agent` com papel tipado.
