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

## Clarify em subagente: consolidar perguntas na tool nativa de pergunta interativa

Quando `/speckit.clarify` roda dentro de um subagente delegado (ex.: pelo modo `arquiteto`, por um
`investigador-*` ou `executor-*`), o subagente **não faz perguntas inline** ao longo da varredura —
ele não é a sessão que conversa com o usuário, e perguntas soltas no meio da delegação quebram o
fluxo do orquestrador.

Fluxo correto:

1. O subagente varre o `spec.md` inteiro, levanta **todas** as ambiguidades (`[NEEDS CLARIFICATION]`,
   requisitos subespecificados) e consolida numa lista única de perguntas — não pausa para perguntar
   uma de cada vez nem resolve por conta própria com suposição.
2. Devolve essa lista para a sessão principal, sem editar o `spec.md` ainda.
3. A sessão principal usa a **tool nativa de pergunta interativa do CLI** para apresentar todas as
   perguntas de uma vez e coletar as respostas do usuário. O nome da tool depende do CLI em uso:

   | CLI | Tool nativa |
   |---|---|
   | Claude Code | `AskUserQuestion` (aceita várias perguntas numa chamada) |
   | Kilo Code | `question` (recebe um array de perguntas — mandar a lista consolidada numa chamada só) |
   | Codex CLI | nenhuma nativa ainda (feature em aberto) — perguntar em texto livre no chat |

   **Confira o nome antes de usar.** A tabela é um instantâneo datado — nome de tool muda entre versões do
   CLI. Liste o toolset da sessão e use a tool de pergunta interativa que existir de fato; se não houver
   correspondência exata, use a genérica de pergunta disponível. Texto livre no chat é o último recurso
   (só quando não existe mecanismo interativo), nunca o primeiro: é justamente o modo degradado que este
   passo existe para evitar.

4. Com as respostas, a sessão principal decide o próximo passo: atualiza o `spec.md` com as decisões
   (fecha o `clarify`) e então segue a árvore de decisão normalmente — ou re-delega ao subagente se
   alguma resposta abrir necessidade de nova investigação.

**Sem `arquiteto` / sem delegação:** se o `/speckit.clarify` roda direto na sessão main (skill
carregada sem passar por subagente), o passo 1 (consolidar todas as ambiguidades numa lista única
antes de perguntar) continua valendo — não pule direto para a primeira pergunta encontrada. A
diferença é só o passo 2: como a própria sessão main é quem decide, ela pode abrir a interação
(tool nativa da tabela acima) diretamente com a lista consolidada, sem precisar "devolver" a
pergunta para si mesma.

**Modo silencioso/autônomo (agente responde sem o usuário):** quando uma instrução explícita manda
resolver as clarificações sem consultar ninguém, o registro padrão `- Q: ... → A: ...` fica
indistinguível de uma resposta que veio de fato do usuário — enganoso meses depois, na leitura do
repositório. Marcar cada bullet do `## Clarifications` com a autoria e a base da decisão, ex.:
`- Q: ... → A: ... (resolvida pelo agente, base: <precedente/arquivo/convenção>)`. Um registro de
decisão que não distingue quem decidiu perde a informação mais importante para quem lê depois — a
confiança que se pode depositar nela.

Regra de escolha nesse modo: cada pergunta auto-respondida recebe a opção **conservadora / de status quo**
— a que menos altera comportamento observável e é mais fácil de reverter. A opção que amplia escopo nunca
é default. E o relatório de retorno ganha uma seção própria, separada do `## Clarifications`, listando
cada pergunta auto-respondida e a base da escolha: sem essa lista, "confirmar com humano" vira uma
releitura atenta do spec em vez de um passo explícito do fluxo.

## Regras de ouro

1. **Nunca pular `clarify` com spec ambíguo.** Ambiguidade não resolvida no spec vira decisão
   arbitrária no plan e retrabalho no código.
2. **`analyze` é gate, não relatório.** Rodou e apontou inconsistência: corrigir o artefato de origem
   e rodar de novo — não seguir para a implementação "sabendo do problema".
3. **`constitution` é global, o resto é por feature.** Uma constitution por repo, em
   `.specify/memory/`; um diretório `specs/NNN-*/` por feature.
4. **Artefato é fonte da verdade, não o chat.** Se a decisão não está no `spec.md`/`plan.md`, ela não
   existe para o próximo passo.
5. **`caminho:símbolo` citado em artefato de design vem de busca no código, não do nome plausível do
   arquivo.** Verificar por grep antes de escrever a primeira vez — e sobretudo antes de repetir o
   mesmo fato num segundo artefato (`plan.md`, `contracts/*`, `data-model.md` frequentemente citam a
   mesma constante/função). O custo de verificar é constante; o custo de corrigir cresce com o número
   de artefatos que já repetiram o palpite.
6. **Superfície "configurável" citada em artefato precisa existir no contrato, não só na prosa.** Se
   `data-model.md`/`contracts/` mandam um diagnóstico ou comportamento respeitar um valor configurável
   (limite, default, modo), confirme que esse valor tem propriedade correspondente no tipo público que o
   consumidor realmente toca, por design e não por descrição. Prosa que promete configuração sem
   superfície de configuração é requisito que não pode ser satisfeito — e isso só aparece na
   implementação, depois de virar tarefa.
7. **Tensão lógica entre casos irmãos é sinal de artefato inconsistente, não detalhe de implementação.**
   Quando a leitura literal de um artefato torna um dos seus próprios casos inalcançável (ex.: uma cadeia
   de precedência com fallback "sempre resolve" e um diagnóstico cuja condição de disparo depende de a
   resolução falhar), trate como contradição a resolver NO artefato — com uma nota curta em
   `data-model.md`/contrato — antes de gerar tarefas contra ele. As dependências entre tarefas do
   `tasks.md` são pista legítima para reconciliar a intenção, mas reconciliar só no código deixa um
   julgamento que o revisor tem de refazer a partir de vários documentos.
8. **Tarefa gerada não pode estreitar o acceptance scenario que diz satisfazer.** Ao gerar/validar
   `tasks.md`, confronte cada tarefa com o texto LITERAL do cenário de aceitação de origem — não com o
   resumo do checkpoint dela. Cenário cujo teste atravessa dois eixos de configuração (dois enums/políticas
   que interagem) é onde a paráfrase mais estreita: ou a tarefa reafirma a condição completa, ou declara
   explicitamente a redução e aponta a tarefa que fecha a lacuna. Um executor mandado seguir `tasks.md` ao
   pé da letra não tem caminho para corrigir isso sem violar o escopo autorizado.

## Verificação antes de concluir

Releia esta skill contra o artefato que você acabou de produzir — ou antes de delegar a implementação:

- Todo `caminho:símbolo` citado foi verificado por grep, não inferido do nome plausível do arquivo?
- Toda superfície citada como "configurável" existe no tipo de contrato público, e não apenas em prosa?
- Cada tarefa foi confrontada com o texto literal do acceptance scenario que diz satisfazer?
- Se houve decisão tomada pelo agente, ela está marcada com autoria e base, e listada no relatório de retorno?
- Se o repo tem `data-model.md`/`contracts/`, eles entraram na varredura do `analyze` (ver
  `docs/comandos.md`), e não só `spec.md`/`plan.md`/`tasks.md`?

## Referências

- `docs/comandos.md` — os 10 comandos: pré-condição, artefato produzido, armadilhas.
- `docs/instalacao.md` — instalação e atualização do `specify` CLI (uv, Windows/PowerShell), `specify init`, troubleshooting.
