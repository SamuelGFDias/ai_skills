---
name: atividade-factory
description: Coleta a atividade de commits (GitLab, via glab) de um projeto ou de todos os repositórios autenticados num período, agrupa por funcionalidade (ou outro critério pedido), cruza com TODO o histórico de issues do usuário (qualquer estado — abertas e fechadas) para não duplicar, e abre issues no padrão da issue-factory — usando hierarquia nativa (issue core + Tasks filhas por commit) para servir como comprovação de serviço auditável. Use quando o usuário pedir para registrar/documentar o que já foi trabalhado, levantar atividade de commits para virar issue, ou comparar commits feitos com issues já existentes (mesmo fechadas).
---

# Skill: atividade-factory

**Tipo:** internal

## Quando executar

Quando o usuário pedir para:
- Levantar/registrar a atividade de commits de um período (própria ou de um projeto) para virar issue.
- Saber "o que já fiz" antes de abrir issues, comparando com TODAS as issues do usuário (abertas e fechadas) para não duplicar.
- Gerar comprovação de serviço a partir do histórico de commits (auditoria de trabalho executado).

Roda em dois modos:
- **Projeto único**: dentro de um repositório específico (ou apontando `--project`).
- **Global**: todos os repositórios do GitLab autenticado via `glab` (como neste histórico de
  desenho da skill — ver memória de projeto referenciada no fim deste arquivo).

## Aviso de custo — leia antes de rodar

A etapa de agrupamento por funcionalidade é **delegada por projeto** a subagentes (ver
"Delegação via arquiteto" abaixo), porque exige julgamento (não é parsing determinístico).
**Aumentar o período aumenta e muito o número de commits e, portanto, o número de chamadas e
tokens gastos.** Para um levantamento diário/semanal de rotina, o custo é baixo; pedir "todo o
histórico da conta" (meses) multiplica o número de subagentes e o tamanho de cada prompt.
Sempre que o período pedido for maior que ~30 dias, avisar o usuário do custo estimado antes
de disparar a coleta.

## Visão geral do fluxo

```
1. Resolver identidade do autor (e-mails)         → scripts/scan_author_identities.py
2. Coletar commits brutos (determinístico)        → scripts/collect_commits.py
3. Coletar TODAS as issues do usuário, qualquer estado (determinístico) → scripts/collect_user_issues.py
4. Agrupar por critério (padrão: funcionalidade), excluir fora de escopo/config,
   cruzar com todas as issues (qualquer estado) — DELEGADO por projeto, ver "Delegação via arquiteto"
5. Decidir granularidade por tema (core+tasks vs. issue única) — ver regra abaixo
6. Criar as issues — ENCADEIA a skill issue-factory (anti-duplicata, título, labels)
   + providers/gitlab/arquivos.md desta skill (hierarquia de Tasks, link "relates_to")
```

### Passo 1 — Identidade do autor

Nunca assumir que a atividade do usuário está toda sob um único `author_email`. Rodar
`scripts/scan_author_identities.py --since <data>` e **confirmar com o usuário** quais e-mails
retornados são realmente dele antes de seguir — um e-mail esquecido gera falso-negativo
silencioso (projeto aparece com zero commits do autor, sem erro nenhum).

### Passo 2 e 3 — Coleta bruta

Rodar `collect_commits.py` e `collect_user_issues.py` apontando para uma pasta de trabalho
temporária **interna a esta skill** (nunca fora dela, nunca no repo do usuário):

```
~/.config/ai/skills/atividade-factory/tmp/<YYYY-MM-DD>-<slug-do-pedido>/
    commits/<project_id>.json
    commits/_index.json
    issues/<project_id>.json
```

Esse diretório é ignorado pelo git (`tmp/` no `.gitignore` do repo de skills) — nunca sobe
para o repositório de skills nem para o projeto do usuário. Ao final do fluxo (issues criadas
e conferidas), apagar a pasta da rodada.

### Passo 4 — Agrupamento e cruzamento com issues (critério do usuário)

**Padrão: agrupar por funcionalidade/tema de trabalho** (não por data, não por projeto isolado
sem tema). Se o usuário pedir outro critério no momento da execução (ex.: por sprint, por
tipo de mudança, por módulo do sistema), usar o critério pedido em vez do padrão.

Regras de agrupamento (não negociáveis, independente do critério escolhido):
- **Excluir do agrupamento** commits que sejam só bump de versão, lint/formatação, merge
  trivial, config mínima (`.gitignore`, CI sem lógica nova) — sem entrega de funcionalidade.
  Listar esses à parte como "fora de escopo/config", nunca simplesmente descartar sem
  registrar (o usuário pode discordar da classificação).
- **Não abstrair a granularidade do commit para dentro do nome do grupo.** O objetivo é
  comprovação de serviço: cada commit (sha curto + link + data) precisa continuar
  identificável dentro do grupo, não virar só uma frase-resumo que apaga a autoria pontual.
- Cruzar cada grupo com TODAS as issues do usuário nesse projeto, qualquer estado (arquivo
  `issues/<project_id>.json`) — **issue fechada que já documentou o mesmo trabalho é
  duplicata do mesmo jeito que uma aberta.** Esta skill audita trabalho já feito; as issues
  que ela cria nascem fechadas (Passo 6), então filtrar só por abertas no cruzamento
  reintroduz exatamente a duplicata que a skill existe para evitar.
  correspondência clara → apontar `#iid` + URL; correspondência parcial → registrar como
  observação, não como cobertura; nenhuma correspondência → candidato a nova issue.

### Delegação via arquiteto

Esta etapa **segue as regras da skill `arquiteto`** para a delegação (ler `arquiteto/SKILL.md`
se ainda não estiver carregada nesta sessão): um subagente `investigador-padrao` por projeto
grande, e projetos pequenos (poucos commits) **consolidados num único subagente** por regra
de orçamento (regra 12 do arquiteto — evitar overhead de muitas chamadas pequenas). Cada
prompt de subagente:
- É read-only (o subagente só lê os JSONs de `commits/` e `issues/`, nunca edita nada).
- Traz o contrato de retorno padrão do arquiteto (`Resultado / Arquivos tocados / Comandos
  rodados / Evidência / Riscos e pendências`).
- Pede evidência granular por commit dentro de cada grupo — não só o nome do grupo.

### Passo 5 — Granularidade: core+Tasks vs. issue única

Depois de agrupado, decidir por tema:

| Tamanho do grupo | Estrutura a criar |
|---|---|
| ≥ ~5 commits | **Issue core** (o tema/objetivo) + **1 Task filha nativa por commit ou por pequeno cluster**, cada uma com sha curto + link + data no corpo (ver provider — hierarquia nativa via GraphQL, disponível mesmo em GitLab CE sem licença). |
| < ~5 commits | **1 issue única**, com checklist de commits (sha curto + link) no corpo — sem Task filha separada. |

**Corpo da issue core (core+tasks) NÃO repete a lista de commits.** Os commits já aparecem
granularmente como Tasks filhas (widget "Child items" do GitLab) — repetir a lista no corpo da
issue core é redundância pura, não redundância de segurança. O corpo da issue core traz só:
objetivo (o que o tema entrega) e escopo (subitens/US cobertos), terminando com algo como
"Detalhamento por commit nas Tasks abaixo." Só a issue **única** (sem Tasks) leva o checklist
de commits no corpo — ali é a única evidência granular que ela tem.

**Tasks filhas nascem abertas — fechar explicitamente é passo obrigatório, não implícito.**
`stateEvent: CLOSE` na issue core não fecha os work items filhos (achado real: numa execução
com 7 issues core+tasks, 3 delas deixaram 28 Tasks filhas abertas por a instrução de fechamento
ter sido lida como aplicável só à issue core). Depois de fechar a issue core, iterar sobre cada
Task filha e fechar via GraphQL `workItemUpdate(stateEvent: CLOSE)` individualmente (mesmo
mecanismo do "Fechar uma Task" no provider) — nunca assumir que o fechamento é recursivo.

Quando o grupo já tem cobertura parcial por uma issue **já existente (aberta OU
fechada)**, **não criar issue nova**: linkar como "relates_to" (ver provider) e registrar a
sobreposição para o usuário decidir se reaproveita a existente. Quando o grupo tem cobertura
**total** por uma issue já existente — **fechada é o caso mais comum**, já que esta skill
audita trabalho já feito e outras issues do mesmo trabalho tendem a já estar fechadas também
—, também não criar issue nova: em vez disso, adicionar um comentário de solução na issue
existente (fluxo "Adicionar Comentário com Solução" da `issue-factory`) com a evidência dos
commits, e usar `set_issue_dates.py` para preencher `start_date`/`due_date` nela se ainda não
tiver (reabre/fecha automaticamente se necessário).

**Datas obrigatórias — sempre a partir dos commits, nunca da data de criação da issue.** Toda
issue criada por esta skill (core ou única) leva `start_date` = data do commit mais antigo do
grupo e `due_date` = data do commit mais recente do grupo (mesmo dia, em grupos de 1 commit).
Isso é o que torna a issue uma comprovação de serviço real — a data tem que refletir quando o
trabalho foi feito, não quando a issue foi registrada no tracker. Usar
`scripts/set_issue_dates.py` (GraphQL `workItemUpdate`, único método que funciona no GitLab
18.x — REST não suporta `start_date`). Cada Task filha, se o grupo virar core+tasks, leva sua
própria data (a do commit que ela representa) via o mesmo script.

### Passo 6 — Criação das issues

Encadear a skill **`issue-factory`** (ler `issue-factory/SKILL.md` e o provider do tracker em
uso, ex. `issue-factory/providers/gitlab/arquivos.md`) para: verificar duplicata, formato de
título (`Módulo - Ação`, nunca mensagem de commit crua), labels de status + projeto, coleta de
assignee/milestone junto ao usuário.

**Ordem de execução por issue (core ou única) — o trabalho já foi feito, isso é registro
retroativo, não backlog futuro:**

1. Criar a issue (`glab issue create`, aberta).
2. Criar as Tasks filhas, se o grupo for core+tasks (`create_child_tasks.py`).
3. Definir `start_date`/`due_date` **enquanto a issue ainda está aberta**
   (`set_issue_dates.py`) — fazer isso antes de fechar evita o ciclo REOPEN→CLOSE do GitLab
   para alterar data em issue fechada. O mesmo vale para cada Task filha, com a data do commit
   que ela representa.
4. Adicionar comentário de solução (fluxo `issue-factory`) resumindo o que foi entregue.
5. Fechar a issue (fluxo `issue-factory`) — o trabalho já está pronto, não fica em `Backlog`.
6. **Se o grupo for core+tasks: fechar CADA Task filha individualmente.** Fechar a issue core
   não fecha os work items filhos — ver "Fechar as Tasks filhas" no provider. Sem este passo,
   as Tasks ficam abertas sob uma issue core já fechada, quebrando a leitura de "tudo concluído".

Para a hierarquia de Tasks e os links "relates_to", usar os comandos concretos e scripts desta
skill em `providers/gitlab/arquivos.md`.

## Scripts de apoio

Ficam em `scripts/` (ver docstring de cada um para uso completo):

- `scan_author_identities.py` — descobre e-mails de autor distintos usados pela mesma pessoa.
- `collect_commits.py` — coleta bruta de commits por projeto/período/autor (determinístico).
- `collect_user_issues.py` — coleta bruta de TODAS as issues do usuário (assigned + created,
  qualquer estado), por projeto.
- `create_child_tasks.py` — cria Tasks filhas nativas sob uma issue core via GraphQL.
- `link_related_issue.py` — cria link "relates_to" entre issues via REST.
- `set_issue_dates.py` — define `start_date`/`due_date` a partir do range de datas dos
  commits do grupo (GraphQL, único método que funciona em GitLab 18.x).

Nenhum desses scripts decide "o que é funcionalidade" — isso é sempre julgamento delegado
(Passo 4). Eles existem só para tirar do modelo o trabalho mecânico de chamar API e parsear
JSON, que não precisa de raciocínio e custaria tokens à toa.

## Providers

- **GitLab SES-RJ** → `providers/gitlab/arquivos.md` (comandos concretos: host, hierarquia
  nativa de work items mesmo sem licença Enterprise, GraphQL de Tasks/links).

## Referência de desenho

O racional completo desta skill (requisitos originais do usuário, decisão de usar hierarquia
nativa de work items em vez de só "related issues", descoberta dos e-mails múltiplos de autor)
está registrado em memória de projeto:
`~/.claude/projects/-home-samuel-dias/memory/project_skill_atividade_commits_issues.md`.
