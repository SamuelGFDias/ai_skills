---
name: speckit
description: Spec-Driven Development com o GitHub Spec Kit — decide QUAL comando /speckit.* rodar a partir do estado dos artefatos do repo (.specify/, constitution, spec/plan/tasks), em que ordem, e quando não usar Spec Kit. Use ao iniciar feature nova sob SDD, ao encontrar specs/ ou .specify/ no repo, ao instalar/atualizar o specify CLI, ou quando pedirem spec, plano, tasks, constitution, clarify, analyze, converge.
---

# Skill: speckit

**Tipo:** internal

## Quando executar

- Ao iniciar uma feature que vai seguir Spec-Driven Development (SDD).
- Ao encontrar `.specify/` ou `specs/` num repo e precisar saber em que ponto do fluxo ele está.
- Quando pedirem para instalar, verificar ou atualizar o `specify` CLI.
- Quando citarem `/speckit.*`, "spec kit", "spec-driven", constitution, spec, plan, tasks, clarify, analyze, converge.

## Modelo mental

O Spec Kit é uma **máquina de estados sobre artefatos em disco**, não um roteiro fixo. Cada comando tem
uma pré-condição (artefato que precisa existir) e produz um artefato. Logo: **não se escolhe o próximo
comando pelo que foi pedido, e sim pelo que já existe no repo.** Constate o estado antes de decidir.

Layout produzido pelo `specify init`:

```text
.specify/
├── memory/constitution.md     # princípios do projeto (/speckit.constitution)
└── templates/                 # + overrides/, presets/, extensions/
.claude/commands/              # os slash commands (integração claude)
specs/NNN-nome-da-feature/
├── spec.md                    # o quê + user stories   (/speckit.specify)
├── plan.md                    # como + stack           (/speckit.plan)
├── tasks.md                   # tarefas ordenadas      (/speckit.tasks)
└── checklists/requirements.md # gate de qualidade      (/speckit.checklist)
```

## Árvore de decisão — estado constatado → próximo comando

Percorra de cima para baixo e pare na primeira linha que casar.

| Constatação | Próximo passo |
|---|---|
| `specify --version` falha | Instalar o CLI → `docs/instalacao.md` |
| não existe `.specify/` na raiz | `specify init --here --force --non-interactive --integration claude` |
| `.specify/memory/constitution.md` ausente, vazio ou ainda com placeholders do template | `/speckit.constitution` |
| feature nova e não há `specs/NNN-*/` correspondente | `/speckit.specify` |
| `spec.md` contém `[NEEDS CLARIFICATION]`, `TODO`, ou requisito ambíguo | `/speckit.clarify` — **sempre antes do plan** |
| `spec.md` limpo e sem `plan.md` | `/speckit.plan` |
| `plan.md` pronto, feature de risco alto ou requisitos densos | `/speckit.checklist` |
| `plan.md` pronto e sem `tasks.md` | `/speckit.tasks` |
| `spec.md` + `plan.md` + `tasks.md` presentes, antes de escrever código | `/speckit.analyze` — read-only, gate de consistência |
| `tasks.md` aprovado e o gate passou | implementar (ver "Implementação" abaixo) |
| código já existe e divergiu dos artefatos | `/speckit.converge` |
| tarefas precisam virar issues no GitHub | `/speckit.taskstoissues` |

Evidências para constatar cada estado: `ls .specify specs`, `git status --short`,
`grep -n 'NEEDS CLARIFICATION\|TODO' specs/*/spec.md`, `specify --version`.

## Caminho curto vs completo

- **Completo (9 passos)** — feature grande, nova área do sistema, mais de uma pessoa envolvida:
  `constitution → specify → clarify → plan → checklist → tasks → analyze → implement → converge`.
- **Curto (5 passos)** — feature pequena e bem entendida, `constitution` já existente:
  `specify → plan → tasks → implement → converge`. Pula `clarify`, `checklist` e `analyze`.

A escolha é por **incerteza**, não por tamanho de código: requisito ambíguo puxa `clarify` mesmo em
feature pequena; requisito trivial dispensa `analyze` mesmo em feature grande.

## Quando NÃO usar Spec Kit

Bugfix pontual, chore, bump de dependência, renomeação, ajuste de config, mudança mecânica em lote.
O ciclo spec+plan+tasks custa mais do que a mudança — vá direto ao código. Spec Kit se paga quando
**o que construir** ainda está em aberto, não quando só falta digitar.

## Implementação: `/speckit.implement` vs delegação pelo arquiteto

`/speckit.implement` executa o `tasks.md` inteiro num agente só. Isso colide com a regra 7 da skill
`arquiteto` (muitas mini-tarefas, um critério de pronto cada) e com a regra 9 (um agente por área
de arquivo).

- **Em modo arquiteto:** não rodar `/speckit.implement`. O `tasks.md` é a entrada do arquiteto —
  ele delega cada tarefa (ou lote sem conflito de arquivo) a um `executor-*` e roda o gate completo
  uma vez ao final (regra 10). O Spec Kit entrega o plano; a orquestração é do arquiteto.
- **Fora do modo arquiteto, ou feature trivial:** `/speckit.implement` direto é aceitável.

Depois de implementar por qualquer um dos dois caminhos, `/speckit.converge` reconcilia os artefatos
com o que o código virou de fato.

## Clarify em subagente: consolidar perguntas com AskUserQuestion

Quando `/speckit.clarify` roda dentro de um subagente delegado (ex.: pelo modo `arquiteto`, por um
`investigador-*` ou `executor-*`), o subagente **não faz perguntas inline** ao longo da varredura —
ele não é a sessão que conversa com o usuário, e perguntas soltas no meio da delegação quebram o
fluxo do orquestrador.

Fluxo correto:

1. O subagente varre o `spec.md` inteiro, levanta **todas** as ambiguidades (`[NEEDS CLARIFICATION]`,
   requisitos subespecificados) e consolida numa lista única de perguntas — não pausa para perguntar
   uma de cada vez nem resolve por conta própria com suposição.
2. Devolve essa lista para a sessão principal, sem editar o `spec.md` ainda.
3. A sessão principal usa `AskUserQuestion` para apresentar todas as perguntas de uma vez e coletar
   as respostas do usuário.
4. Com as respostas, a sessão principal decide o próximo passo: atualiza o `spec.md` com as decisões
   (fecha o `clarify`) e então segue a árvore de decisão normalmente — ou re-delega ao subagente se
   alguma resposta abrir necessidade de nova investigação.

## Regras de ouro

1. **Nunca pular `clarify` com spec ambíguo.** Ambiguidade não resolvida no spec vira decisão
   arbitrária no plan e retrabalho no código.
2. **`analyze` é gate, não relatório.** Rodou e apontou inconsistência: corrigir o artefato de origem
   e rodar de novo — não seguir para a implementação "sabendo do problema".
3. **`constitution` é global, o resto é por feature.** Uma constitution por repo, em
   `.specify/memory/`; um diretório `specs/NNN-*/` por feature.
4. **Artefato é fonte da verdade, não o chat.** Se a decisão não está no `spec.md`/`plan.md`, ela não
   existe para o próximo passo.

## Referências

- `docs/comandos.md` — os 10 comandos: pré-condição, artefato produzido, armadilhas.
- `docs/instalacao.md` — instalação e atualização do `specify` CLI (uv, Windows/PowerShell), `specify init`, troubleshooting.
