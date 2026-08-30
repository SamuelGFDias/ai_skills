# Provider: GitLab (SES-RJ)

Comandos concretos para o fluxo genérico de `issue-factory` quando o tracker é o GitLab do
SES-RJ (`glab` CLI). Ler antes de executar qualquer comando `glab`/`glab api` deste provider.

## Pré-requisitos

- `glab` CLI instalado e autenticado no `gitlab-prod.saude.rj.gov.br`.
- Grupo: `ses-rj/desenvolvimento` (`group_id=6`).
- Projetos dentro deste grupo (ex: `ses-rj/desenvolvimento/biae/biae`,
  `ses-rj/desenvolvimento/amaq/amaq`, etc.).
- Usuários já existentes no GitLab (ver tabela de atribuição abaixo).

## Coleta de informações interativas

Mapeamento dos itens genéricos do `SKILL.md` para o GitLab:

| Item genérico | Onde vive no GitLab | Padrão |
|---|---|---|
| Usuário (assignee) | — | — |
| Milestone | Grupo `/groups/ses-rj/desenvolvimento/` (compartilhado entre subprojetos) | — |
| Projeto | — | `ses-rj/desenvolvimento/biae/biae` |
| Label de status (`Backlog`, `In progress`, `Offside`, `Pause`) | Grupo `/groups/ses-rj/` | — |
| Label do projeto (ex: `Biae`, `Amaq`) | Grupo `/groups/ses-rj/desenvolvimento/` | — |

Diferente do GitHub, labels e milestones no GitLab **têm escopo de grupo**, não só de projeto —
por isso a distinção entre `/groups/ses-rj/` (labels de status, transversais) e
`/groups/ses-rj/desenvolvimento/` (labels de projeto + milestones, compartilhados entre
subprojetos) importa na hora de criar/listar.

## Fluxo — Verificar autenticação

```bash
glab auth status
```

## Fluxo — Criar Issue

Montar **label de status** + **label do projeto** separadas por vírgula:

```bash
-l "<label-projeto>,<label-status>"
```

Exemplo: `-l "Biae,Backlog"`.

Como `glab issue create -d` pode truncar descrições longas ou corromper acentuação, salvar o
corpo em arquivo temporário UTF-8 e usar `-d "$(cat ...)"` (o `glab` não tem um `--body-file`
nativo equivalente ao `gh issue create -F` do provider GitHub):

```bash
mkdir -p .kilo/tmp

cat > .kilo/tmp/issue_desc.md << 'EOF'
**US (História de Usuário):** ...

**Solução:**

...
EOF

glab issue create \
  -R ses-rj/desenvolvimento/biae/biae \
  -t "Título da demanda" \
  -d "$(cat .kilo/tmp/issue_desc.md)" \
  -l "Biae,Backlog" \
  -a wallace.fortuna

rm -f .kilo/tmp/issue_desc.md
```

Se um milestone foi informado, atribuir depois de criar:

```bash
glab issue update <iid> -R ses-rj/desenvolvimento/biae/biae --milestone "NomeDoMilestone"
```

> `-R` aceita qualquer projeto em `ses-rj/desenvolvimento` (ex:
> `ses-rj/desenvolvimento/amaq/amaq`, `ses-rj/desenvolvimento/talonario/talonario`).

## Fluxo — Adicionar Comentário com Solução

Antes de fechar uma issue, registrar a solução como comentário:

```bash
glab issue note <iid> \
  -R ses-rj/desenvolvimento/biae/biae \
  -m "## Solução implementada

**Commit:** <hash>

Descrição técnica do que foi feito.

**Arquivos alterados:**
- \`caminho/do/arquivo\`"
```

## Fluxo — Fechar Issue

### Via `glab` (simples)

```bash
glab issue update <iid> -R ses-rj/desenvolvimento/biae/biae --unlabel "In progress"
glab issue close <iid> -R ses-rj/desenvolvimento/biae/biae
```

### Via GraphQL (quando precisar manipular datas junto)

Depois de fechada, campos como `due_date`/`start_date` **não podem ser alterados** via REST ou
`glab issue update`. Usar `stateEvent: REOPEN` antes de definir datas, depois `stateEvent: CLOSE`
para fechar de novo (ver "Definir Datas" abaixo, Passo 3).

## Fluxo — Atribuir Milestone

Milestones pertencem ao grupo `/groups/ses-rj/desenvolvimento/` — compartilhados entre projetos.

```bash
# Atribuir uma issue a um milestone
glab issue update <iid> -R ses-rj/desenvolvimento/biae/biae --milestone "Julho/2026"

# Atribuir várias issues no mesmo projeto
for iid in 1 2 3 4 5; do
  glab issue update "$iid" -R ses-rj/desenvolvimento/amaq/amaq --milestone "Julho/2026"
done
```

Criar milestone no projeto, se não existir:

```bash
glab api -X POST "projects/ses-rj%2Fdesenvolvimento%2Fbiae%2Fbiae/milestones" \
  --raw-field title="Agosto/2026" \
  --raw-field description="Milestone referente ao mês de Agosto de 2026" \
  --raw-field start_date="2026-08-01" \
  --raw-field due_date="2026-08-31"
```

## Fluxo — Definir Datas (start_date / due_date)

### `due_date` apenas (issue nova ou aberta)

`glab issue update` suporta `--due-date` diretamente:

```bash
glab issue update <iid> -R ses-rj/desenvolvimento/biae/biae --due-date 2026-07-14
```

### `start_date` — GraphQL (único método)

> Nem o `glab` CLI (até v1.111.0) nem a REST API suportam `start_date` no GitLab 18.x.
> `glab issue update` só tem `--due-date`, sem `--start-date`. A REST API só aceita `start_date`
> a partir do **GitLab 19.1**. Único método funcional em 18.x: **GraphQL** via `workItemUpdate`.

**Passo 1 — obter o ID global do work item:**

```bash
glab api "projects/ses-rj%2Fdesenvolvimento%2Fbiae%2Fbiae/issues/<iid>" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])"
```

O ID retornado (ex: `849`) vira `gid://gitlab/WorkItem/<id>`.

**Passo 2 — definir datas via mutação GraphQL (issue aberta):**

```bash
glab api graphql -f query='
mutation {
  workItemUpdate(input: {
    id: "gid://gitlab/WorkItem/<ID_GLOBAL>",
    startAndDueDateWidget: { startDate: "2026-07-14", dueDate: "2026-07-14" }
  }) { errors }
}
'
```

**Passo 3 — issue fechada: reabrir, definir datas e fechar de novo:**

```bash
glab api graphql -f query='
mutation {
  workItemUpdate(input: {
    id: "gid://gitlab/WorkItem/<ID_GLOBAL>",
    stateEvent: REOPEN,
    startAndDueDateWidget: { startDate: "2026-07-14", dueDate: "2026-07-14" }
  }) { errors }
}
'

glab api graphql -f query='
mutation {
  workItemUpdate(input: { id: "gid://gitlab/WorkItem/<ID_GLOBAL>", stateEvent: CLOSE }) { errors }
}
'
```

**Definir datas em lote (múltiplas issues, inclusive fechadas):**

```bash
# 1) Obter IDs globais de uma vez
for iid in 40 41 42; do
  id=$(glab api "projects/ses-rj%2Fdesenvolvimento%2Fbiae%2Fbiae/issues/$iid" \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
  echo "$iid $id"
done

# 2) Reabrir + definir datas por ID global
glab api graphql -f query='
mutation {
  workItemUpdate(input: {
    id: "gid://gitlab/WorkItem/849",
    stateEvent: REOPEN,
    startAndDueDateWidget: { startDate: "2026-07-14", dueDate: "2026-07-14" }
  }) { errors }
}
'

# 3) Fechar todas em lote
for id in 849 850 851; do
  glab api graphql -f query='
  mutation {
    workItemUpdate(input: { id: "gid://gitlab/WorkItem/'"$id"'", stateEvent: CLOSE }) { errors }
  }
  '
done
```

**Validar datas definidas:**

```bash
glab api graphql -f query='
query {
  workItem(id: "gid://gitlab/WorkItem/<ID_GLOBAL>") {
    id
    widgets { ... on WorkItemWidgetStartAndDueDate { startDate dueDate } }
  }
}
'
```

## Fluxo — Buscar Issues por Usuário em Todos os Projetos do Grupo

```bash
# Listar todos os projetos do grupo
glab api "groups/ses-rj%2Fdesenvolvimento/projects?per_page=100&include_subgroups=true"

# Buscar issues de um usuário específico num intervalo de datas
glab api "groups/ses-rj%2Fdesenvolvimento/issues?per_page=100&state=all&assignee_username=samuel.dias&created_after=2026-07-01&created_before=2026-07-31"
```

## Fluxo — Descobrir se uma Issue já foi Atribuída a Alguém no Passado

`glab issue list`/`glab api .../issues` só retorna o **estado atual** (`assignee`/`assignees`) —
não existe campo de histórico nesse payload. A Search API (`scope=notes`) também não ajuda:
notas de sistema não são indexadas pela busca, mesmo em projeto único.

A única fonte de verdade é a nota de sistema por issue (`assigned to @user`/`unassigned @user`),
em `/projects/:id/issues/:iid/notes` — exige 1 chamada por issue. Rodar em sequência é lento
(74 issues × ~6s = 7+min); **paralelizar com `xargs -P`** reduz drasticamente o tempo (~3s para
as mesmas 74 issues):

```bash
# 1) Listar issues abertas do grupo e extrair project_id + iid
glab api "groups/ses-rj%2Fdesenvolvimento/issues?per_page=100&state=opened&scope=all" \
  | python3 -c "
import json,sys
for i in json.load(sys.stdin):
    print(f\"{i['project_id']} {i['iid']} {i['references']['full']}\")
" > /tmp/issue_ids.txt

# 2) Script standalone (xargs não herda funções do zsh — precisa de arquivo)
cat > /tmp/check_issue.sh << 'EOF'
#!/usr/bin/env bash
export GITLAB_HOST=gitlab-prod.saude.rj.gov.br
pid="$1"; iid="$2"; ref="$3"
notes=$(glab api "projects/$pid/issues/$iid/notes?per_page=100" 2>/dev/null)
hit=$(echo "$notes" | python3 -c "
import json,sys
try:
    notes = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for n in notes:
    if n.get('system') and 'samuel.dias' in n.get('body','') and 'assign' in n.get('body','').lower():
        print(n['body'])
")
[ -n "$hit" ] && echo "$ref :: $hit"
EOF
chmod +x /tmp/check_issue.sh

# 3) Rodar em paralelo (15 workers é um bom equilíbrio, não satura a API)
cat /tmp/issue_ids.txt | xargs -P 15 -L 1 /tmp/check_issue.sh
```

Troque `samuel.dias` pelo username desejado. O resultado mostra `assigned to @user`/
`unassigned @user` na ordem cronológica das notas — a última entrada é o estado mais recente.

**Nota sobre `--hostname`:** `glab issue update`/`glab issue list` não têm flag `--hostname`.
Fora de um repositório git local (sem remote configurado), `export GITLAB_HOST=gitlab-prod.saude.rj.gov.br`
antes do comando resolve; `glab api` aceita `--hostname` normalmente.

## Fluxo — Atribuir Milestone em Massa para Múltiplos Usuários

```bash
for user in flavio.filho samuel.dias jonatas.rodrigues lucas.jesus victor.pinto; do
  glab api "groups/ses-rj%2Fdesenvolvimento/issues?per_page=100&state=all&assignee_username=$user&created_after=2026-07-01&created_before=2026-07-31" \
    | node -e "
const fs = require('fs');
const data = JSON.parse(fs.readFileSync(0, 'utf8'));
data.forEach(i => console.log(i.project_id + '|' + i.iid));
" | while IFS='|' read -r pid iid; do
    path=$(glab api "projects/$pid" 2>/dev/null | node -e "const fs=require('fs');console.log(JSON.parse(fs.readFileSync(0,'utf8')).path_with_namespace)")
    glab issue update "$iid" -R "$path" --milestone "Julho/2026"
  done
done
```

## Labels e Atribuição

| Grupo GitLab | Labels |
|---|---|
| `/groups/ses-rj/` | `Backlog`, `In progress`, `Offside`, `Pause` |
| `/groups/ses-rj/desenvolvimento/` | Demais labels por projeto (ex: `Biae`, `Amaq`, `Talonario`, `PericiaMedica`) |

Ao criar a issue, sempre incluir: label do projeto (grupo `desenvolvimento/`) + label de status
(grupo raiz `ses-rj/`).

| Usuário | GitLab |
|---|---|
| Wallace Fortuna | `wallace.fortuna` |
| Flavio Filho | `flavio.filho` |
| Samuel Dias | `samuel.dias` |
| Jonatas Rodrigues | `jonatas.rodrigues` |
| Lucas Jesus | `lucas.jesus` |
| Victor Pinto | `victor.pinto` |

## Observações

- Projetos comuns: `biae/biae`, `amaq/amaq`, `agendamedicamentos/agendamedicamentos`,
  `talonario/talonario`, `pericia-medica/pericia-medica`, `crachamaster/crachamaster`,
  `template-dev-ses`, `legados/scp/scp`, `legados/protocolo-online/protocoloonline`,
  `pesquisasatisfacao/pesquisasatisfacao`.
- Sempre usar `-R` com o caminho completo do projeto.
- Para descrições longas ou com acentos, sempre usar arquivo temporário com `-d "$(cat ...)"`.
- Issues e **work items** compartilham o mesmo namespace de IID — `glab issue update` funciona
  para ambos.
- Milestones de grupo (`ses-rj/desenvolvimento`) são acessíveis por todos os subprojetos;
  milestones de projeto são específicos.
- O `group_id` de `ses-rj/desenvolvimento` é `6` (usado em endpoints de grupo).
- **GraphQL vs REST:** a REST API do GitLab 18.x **não** suporta `start_date` em issues (campo
  introduzido só no GitLab 19.1). Usar sempre a mutação GraphQL `workItemUpdate` com
  `startAndDueDateWidget` para definir `start_date`/`due_date` simultaneamente.
- **Issue fechada:** bloqueia alteração de datas via REST/`glab`. Usar GraphQL com
  `stateEvent: REOPEN` → definir datas → `stateEvent: CLOSE`.
