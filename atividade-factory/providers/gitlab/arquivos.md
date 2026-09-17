# Provider: GitLab (SES-RJ)

Comandos concretos para a `atividade-factory` quando o tracker é o GitLab do SES-RJ (`glab`
CLI, host `gitlab-prod.saude.rj.gov.br`). Ler antes de rodar os scripts desta skill ou GraphQL
manual.

## Confirmação de capacidade da instância

Esta instância é **GitLab CE 18.4.2 sem licença** (`enterprise: false` em `glab api version`).
Mesmo assim, o widget nativo **HIERARCHY** existe em `Issue` e o tipo de work item **Task**
está disponível no catálogo de tipos do projeto — confirmado via GraphQL:

```bash
glab api version   # confirma "enterprise": false e a versão
glab api graphql -f query='
query {
  project(fullPath: "<grupo>/<projeto>") {
    workItemTypes { nodes { id name } }
  }
}'
```

Se `workItemTypes` não incluir `"Task"` num projeto específico, cair para o fallback de
"issue única com checklist" (Passo 5 do `SKILL.md`) para esse projeto — não travar o fluxo.

## Passo 1 — Identidade do autor

```bash
python3 scripts/scan_author_identities.py --since 2026-09-01
# revisar a lista de "identities" com o usuário antes de seguir
```

## Passo 2/3 — Coleta bruta

```bash
RUN_DIR=~/.config/ai/skills/atividade-factory/tmp/2026-09-17-setembro
mkdir -p "$RUN_DIR"

python3 scripts/collect_commits.py \
  --since 2026-09-01 \
  --emails samuel.dias@ses.rj.gov.br,samudias48@gmail.com,samuel.dias@extreme.digital \
  --out-dir "$RUN_DIR"

python3 scripts/collect_user_issues.py --out-dir "$RUN_DIR"
```

Sem `--projects`, `collect_commits.py` descobre projetos tocados no período via
`/events?action=pushed`. Para modo "projeto único", passar `--projects <id>` (obter o id com
`glab api projects/<grupo%2Fprojeto> | python3 -c "import json,sys;print(json.load(sys.stdin)['id'])"`).

## Passo 4 — Delegação (ver `arquiteto/SKILL.md` da skill `arquiteto`)

Cada subagente recebe os caminhos de `$RUN_DIR/commits/<pid>.json` e
`$RUN_DIR/issues/<pid>.json` (quando existir) — não o conteúdo inline, para não gastar tokens
do arquiteto reexplicando dado que já está em arquivo.

## Passo 5/6 — Criar a issue core (encadeia `issue-factory`)

Seguir `issue-factory/providers/gitlab/arquivos.md` normalmente (anti-duplicata, título,
labels, assignee). Guardar o `iid` retornado — é o `--parent-iid` do próximo passo.

## Criar as Tasks filhas (hierarquia nativa)

```bash
cat > "$RUN_DIR/tasks_<pid>.json" << 'EOF'
[
  {"title": "9d512706 feat: cria enum EAcaoEducativa para Capacitacao.Acao",
   "description": "Commit 9d512706 (17/09/2026)\nhttps://gitlab-prod.saude.rj.gov.br/ses-rj/desenvolvimento/biae/biae/-/commit/9d512706..."}
]
EOF

python3 scripts/create_child_tasks.py \
  --project ses-rj/desenvolvimento/biae/biae \
  --parent-iid 90 \
  --tasks-file "$RUN_DIR/tasks_<pid>.json"
```

Cada Task criada aparece no widget "Tasks"/"Child items" da issue core no GitLab — dá pra
marcar cada uma como concluída (`stateEvent: CLOSE` via GraphQL, ou pela UI) conforme o
trabalho é validado, sem perder o link para o commit de origem.

### Fechar as Tasks filhas — obrigatório no fluxo desta skill, não opcional

Fechar a issue core **não fecha as Tasks filhas** — são work items independentes. No fluxo de
comprovação de serviço (Passo 6 do `SKILL.md`), depois de fechar a issue core, fechar CADA
Task filha individualmente:

```bash
glab api graphql -f query='
mutation {
  workItemUpdate(input: { id: "<gid da task retornado por create_child_tasks.py>", stateEvent: CLOSE }) { errors }
}'
```

Em lote (uma iid por linha, obtendo o gid via REST antes de cada mutação):

```bash
for iid in 44 45 46 47 48; do
  wid=$(glab api "projects/272/issues/$iid" | python3 -c "import json,sys;print(json.load(sys.stdin)['id'])")
  glab api graphql -f query="mutation { workItemUpdate(input: { id: \"gid://gitlab/WorkItem/$wid\", stateEvent: CLOSE }) { errors } }"
done
```

## Definir datas a partir dos commits (start_date/due_date)

Sempre feito **com a issue ainda aberta**, antes do comentário de solução e do fechamento
(ver ordem no Passo 6 do `SKILL.md`):

```bash
python3 scripts/set_issue_dates.py \
  --project ses-rj/desenvolvimento/biae/biae --iid 90 \
  --start-date 2026-09-01 --due-date 2026-09-17
```

`--start-date` = data do commit mais antigo do grupo; `--due-date` = data do mais recente
(mesmo dia, se o grupo tiver 1 commit só). Repetir para cada Task filha, com a data do commit
que ela representa (`--iid` = iid da Task, retornado por `create_child_tasks.py`).

Se a issue de destino já estiver fechada (ex.: rodando o script de novo depois do Passo 6.5),
o script detecta e faz `REOPEN` → define datas → `CLOSE` automaticamente — não precisa reabrir
manualmente antes de chamar.

## Linkar issue core a uma issue já existente (sobreposição parcial, aberta ou fechada)

Quando o tema já tem issue (aberta ou fechada) cobrindo parte do trabalho (não é duplicata total, mas
também não é candidato a issue nova) — ex.: aih-apac #38 cobre um levantamento mais amplo de
SQL injection que um dos commits corrigiu pontualmente:

```bash
python3 scripts/link_related_issue.py \
  --project ses-rj/desenvolvimento/aih-apac/aih-apac --iid 90 \
  --target-project ses-rj/desenvolvimento/aih-apac/aih-apac --target-iid 38
```

## Limpeza

Depois de criadas e conferidas as issues (issue core + Tasks + links), apagar a pasta da
rodada — ela é só material de trabalho intermediário, não artefato a preservar:

```bash
rm -rf "$RUN_DIR"
```

## Observações

- Reaproveitar a tabela de labels/usuários já documentada em
  `issue-factory/providers/gitlab/arquivos.md` — esta skill não duplica essa tabela.
- `create_child_tasks.py` resolve o `workItemTypeId` de "Task" por projeto a cada chamada
  (não cachear o ID entre projetos — o ID do tipo pode variar por instância/projeto).
- REST não cria work item filho; só GraphQL (`workItemCreate` + `hierarchyWidget.parentId`).
  Link "relates_to" já é REST estável (`/projects/:id/issues/:iid/links`), sem necessidade de
  GraphQL.
