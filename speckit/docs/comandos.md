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

Armadilha: prometer em prosa uma superfície "configurável" (um limite, um default, um modo) sem que
exista propriedade correspondente no tipo público que o consumidor toca. `data-model.md`/`contracts/`
citando "configurável, ver Clarifications" quando o `spec.md` não registra valor e o tipo de contrato
não tem onde receber esse valor gera tarefa impossível de satisfazer literalmente. Toda configuração
prometida precisa de superfície real no contrato antes de virar tarefa.

Armadilha: na seção "Project Structure", listar arquivo novo que usa símbolo de outro arquivo sem
confirmar o mecanismo de linkagem/import contra o build system real (ex.: diretório de teste sem
target de biblioteca para importar). Uma estrutura de arquivos planejada é uma afirmação sobre o
grafo de dependências do build, não só sobre nomes de diretório — confirmar com um comando de
metadados do build (não leitura de código) antes de dar a seção como pronta; se exigir mudança
estrutural (criar target, alargar visibilidade, mover módulo), isso vira task explícita, não
pressuposto implícito.

### `/speckit.checklist`
Gera checklists de qualidade sob medida para validar completude dos requisitos. `requirements.md` é
mantido automaticamente; checklists extras são do revisor.

Quando vale: feature de risco alto, requisito regulatório, integração com sistema externo. Feature
pequena e bem entendida dispensa.

### `/speckit.tasks`
Quebra o plan em tarefas acionáveis ordenadas por dependência. É a entrada natural para a delegação
em mini-tarefas da skill `arquiteto`.

Armadilha: a tarefa parafrasear o acceptance scenario de origem e silenciosamente estreitá-lo. O caso
pior é cenário cujo teste atravessa dois eixos de configuração que interagem (ex.: `SyncMode` ×
`OnBreakingChange`): "computar o resultado e aplicar a política, mas nunca gravar" não é o mesmo que
"falha em QUALQUER divergência, e nada é escrito". Confronte cada tarefa com o texto literal do
cenário, não com o resumo do checkpoint — o executor mandado seguir o `tasks.md` ao pé da letra não
consegue corrigir isso sem sair do escopo autorizado. Ou a tarefa reafirma a condição completa, ou
declara a redução como deliberada e aponta a tarefa que fecha a lacuna.

### `/speckit.analyze`
Consistência e cobertura cruzada entre `spec.md`, `plan.md` e `tasks.md` — requisito sem tarefa,
tarefa sem requisito, plan contradizendo spec. **Não altera arquivo**: é gate, roda antes de codar.

Armadilha: tratar o relatório como informativo. Apontou inconsistência → corrigir o artefato de
origem e rodar de novo.

Armadilha: o gate padrão compara `spec.md`/`plan.md`/`tasks.md`, mas `tasks.md` também é gerado a
partir de `data-model.md`/`contracts/` — dois arquivos que o `analyze` não cobre por padrão. Cada
documento pode ser internamente consistente e ainda divergir do outro (ex.: `tasks.md` tratando um
campo como propriedade do objeto todo enquanto `data-model.md` o define por item da lista).
Consistência interna de um artefato não implica consistência entre artefatos gerados um do outro:
incluir explicitamente `data-model.md`/`contracts/` na varredura — todo nome de campo/tipo citado em
`tasks.md` precisa existir com o mesmo nome e tipo dono ali, e todo tipo/decisão desses dois precisa
ter task correspondente.

Armadilha: comparar a tarefa com o resumo do próprio checkpoint em vez do texto literal do acceptance
scenario que ela diz satisfazer. Cenário cuja condição atravessa dois eixos de configuração é onde a
paráfrase estreita mais. Quando o teste do cenário depender de um fallback "sempre resolve" que a
própria tarefa torna inalcançável, isso é contradição entre artefatos: reporte e corrija o artefato de
origem com uma nota curta, não deixe para o implementador reconciliar lendo três documentos.

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
