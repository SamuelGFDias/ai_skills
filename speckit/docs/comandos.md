# Comandos do Spec Kit — pré-condição → artefato

Referência da skill `speckit`. Todos os comandos são slash commands do agente (arquivos em
`.claude/commands/` na integração claude), instalados por `specify init`. Não são comandos de shell.

## Tabela de referência

| Comando | Pré-condição | Produz | Read-only? |
|---|---|---|---|
| `/speckit.constitution` | `.specify/` existe | `.specify/memory/constitution.md` | não |
| `/speckit.specify` | constitution definida (recomendado) | `specs/NNN-nome/spec.md` | não |
| `/speckit.clarify` | `spec.md` existe | `spec.md` atualizado (ambiguidades resolvidas) | não |
| `/speckit.plan` | `spec.md` sem ambiguidade | `specs/NNN-nome/plan.md` + artefatos de design | não |
| `/speckit.checklist` | `spec.md` (e idealmente `plan.md`) | `specs/NNN-nome/checklists/*.md` | não |
| `/speckit.tasks` | `plan.md` existe | `specs/NNN-nome/tasks.md` (ordenado por dependência) | não |
| `/speckit.analyze` | `spec.md` + `plan.md` + `tasks.md` | relatório de inconsistência | **sim** |
| `/speckit.implement` | `tasks.md` aprovado | código | não |
| `/speckit.converge` | código + artefatos existentes | tarefas novas anexadas ao `tasks.md` | não |
| `/speckit.taskstoissues` | `tasks.md` existe + repo GitHub | issues no GitHub | não |

## Detalhe por comando

### `/speckit.constitution`
Princípios que governam o projeto — o que todo passo posterior é avaliado contra. Roda **uma vez por
repo**; revisita-se quando um princípio muda, não a cada feature.

Armadilha: constitution genérica ("código limpo", "boas práticas") não restringe nada e não filtra
decisão nenhuma no `plan`. Princípio útil é o que **exclui** uma alternativa plausível.

### `/speckit.specify`
Descreve **o quê** e **por quê** — requisitos e user stories. Nunca stack, biblioteca ou desenho de
tabela: isso é `plan`. Cria o diretório `specs/NNN-nome-da-feature/` numerado.

Armadilha: escrever solução disfarçada de requisito ("criar tabela X com colunas Y"). Se a frase cita
tecnologia, provavelmente pertence ao `plan`.

### `/speckit.clarify`
Varre o spec por áreas subespecificadas e resolve, marcando `[NEEDS CLARIFICATION]` onde não conseguir.
**Recomendado sempre antes do `plan`** — é o passo mais barato de todo o ciclo e o que mais evita
retrabalho.

Armadilha: pular por pressa. Ambiguidade não resolvida aqui vira decisão arbitrária no plan.

### `/speckit.plan`
Estratégia técnica: stack, arquitetura, contratos, modelo de dados. É onde a tecnologia entra pela
primeira vez.

Armadilha: rodar com spec ainda ambíguo — o plan preenche a lacuna com um chute plausível e o chute
some dentro de um documento que parece decidido.

### `/speckit.checklist`
Gera checklists de qualidade sob medida para validar completude dos requisitos. `requirements.md` é
mantido automaticamente; checklists extras são do revisor.

Quando vale: feature de risco alto, requisito regulatório, integração com sistema externo. Feature
pequena e bem entendida dispensa.

### `/speckit.tasks`
Quebra o plan em tarefas acionáveis ordenadas por dependência. É a entrada natural para a delegação
em mini-tarefas da skill `arquiteto`.

### `/speckit.analyze`
Consistência e cobertura cruzada entre `spec.md`, `plan.md` e `tasks.md` — requisito sem tarefa,
tarefa sem requisito, plan contradizendo spec. **Não altera arquivo**: é gate, roda antes de codar.

Armadilha: tratar o relatório como informativo. Apontou inconsistência → corrigir o artefato de
origem e rodar de novo.

### `/speckit.implement`
Executa o `tasks.md`. Em modo arquiteto, **não usar** — ver a seção "Implementação" do `SKILL.md`:
o `tasks.md` vira delegação em mini-tarefas para `executor-*`.

### `/speckit.converge`
Compara o código real contra spec/plan/tasks e **anexa** ao `tasks.md` o que ainda falta. É o passo
de fechamento, e também a porta de entrada para adotar Spec Kit num repo que já tem código.

### `/speckit.taskstoissues`
Converte `tasks.md` em issues do GitHub. Para GitLab, o caminho é a skill `issue-factory`
(+ `providers/gitlab/arquivos.md`), não este comando.

## Ordem canônica

```text
constitution ─┐                                    (uma vez por repo)
              └→ specify → clarify → plan → checklist → tasks → analyze → implement → converge
                                                                              ↑
                                              caminho curto pula clarify/checklist/analyze
```
