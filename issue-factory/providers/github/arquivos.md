# Provider: GitHub

Comandos concretos para o fluxo genérico de `issue-factory` quando o tracker é o GitHub
(`gh` CLI). Ler antes de executar qualquer comando `gh` neste provider.

## Pré-requisitos

- `gh` CLI instalado e autenticado (`gh auth status`).
- Repositório no formato `owner/repo` (ex: `SamuelGFDias/condominio_app`). GitHub não tem o
  conceito de "grupo" do GitLab — labels e milestones vivem sempre dentro de um repositório
  específico, nunca compartilhados entre repositórios.
- Escopo `repo` no token (a maioria dos fluxos abaixo já funciona com o escopo padrão de
  `gh auth login`); operações em GitHub Projects (v2) exigem escopo `project`
  (`gh auth refresh -s project`), só necessário se o fluxo de projeto for usado.

## Coleta de informações interativas

Mapeamento dos itens genéricos do `SKILL.md` para o GitHub:

| Item genérico | Equivalente no GitHub | Observação |
|---|---|---|
| Usuário (assignee) | `--assignee <login>` | Aceita `@me` para autoatribuir. Não há atribuição por grupo. |
| Milestone | `--milestone <título>` | Por repositório — precisa existir antes (ver "Criar milestone" abaixo) ou ser criado na hora. |
| Projeto | `owner/repo` (`-R`) | Não existe agrupamento de repositórios como `ses-rj/desenvolvimento` — cada repo é isolado. |
| Label de status | label comum (ex: `in-progress`, `backlog`) | Sem separação de escopo por grupo — todas as labels vivem no mesmo repositório. |
| Label do projeto/módulo | label de domínio (ex: `modulo:iam`, `debito-tecnico`) | Convenção local por repositório — ver labels já criadas com `gh label list -R owner/repo`. |

Sem valor de "grupo" a perguntar — pedir direto **repositório**, **assignee**, **milestone** e
**labels** (status + módulo/domínio), salvo se já informados.

## Fluxo — Verificar autenticação

```bash
gh auth status
```

## Fluxo — Criar labels (idempotente)

```bash
gh label create "<nome>" --color "<hex-sem-#>" --description "<descrição>" --force -R owner/repo
```

`--force` atualiza cor/descrição se a label já existir, em vez de falhar — seguro para rodar
sempre antes de criar issues, sem checar existência primeiro.

## Fluxo — Verificar se já existe issue aberta sobre o assunto (anti-duplicata)

Obrigatório antes de criar qualquer issue (passo 2 do `SKILL.md`). Buscar por termos-chave da
demanda no repositório de destino:

```bash
# No repositório específico — qualificador in:title,body restringe a busca
gh issue list -R owner/repo --state open --search "<termos-chave> in:title,body"

# Alternativa global (busca em todos os repositórios do usuário/organização)
gh search issues --repo owner/repo --state open "<termos-chave>"
```

- `gh issue list --search` usa a mesma sintaxe de qualificadores do `gh search issues`
  (`in:title`, `in:body`, `is:open`, etc.).
- Se a busca retornar correspondência clara, **não criar**: reportar a issue existente ao usuário.
- Por padrão a busca cobre issues e PRs abertos; adicionar `is:issue` para restringir a issues.

## Fluxo — Criar Issue

GitHub tem uma vantagem sobre o GitLab aqui: `gh issue create` aceita `-F/--body-file` nativo,
então não é preciso o truque de `-d "$(cat ...)"` (usado no provider GitLab) para preservar
UTF-8 e evitar truncamento — `--body-file` já lê o arquivo diretamente.

```bash
mkdir -p .tmp

cat > .tmp/issue_desc.md << 'EOF'
## Contexto
...

## Comportamento atual
...
EOF

gh issue create \
  -R owner/repo \
  --title "Título da issue" \
  --body-file .tmp/issue_desc.md \
  --label "modulo:iam,debito-tecnico" \
  --assignee "@me" \
  --milestone "Nome do milestone"

rm -f .tmp/issue_desc.md
```

- `--label` aceita lista separada por vírgula, cada label precisa já existir no repositório
  (criar antes com `gh label create`, ver acima) — diferente do GitLab, não há distinção de
  labels "de grupo" vs. "de projeto", todas vivem no mesmo namespace do repo.
- `--milestone` só funciona se o milestone já existir (ver "Criar milestone" abaixo); passar o
  nome, não o número.
- Sem `-d`/`-b` para corpo longo — sempre `--body-file` quando o corpo tiver Markdown
  estruturado ou acentuação.

## Fluxo — Adicionar Comentário com Solução

```bash
cat > .tmp/comentario.md << 'EOF'
## Solução implementada

**Commit:** <hash>

Descrição técnica do que foi feito.

**Arquivos alterados:**
- `caminho/do/arquivo`
EOF

gh issue comment <numero> -R owner/repo --body-file .tmp/comentario.md
rm -f .tmp/comentario.md
```

## Fluxo — Fechar Issue

```bash
# Remover label de status, se usada
gh issue edit <numero> -R owner/repo --remove-label "in-progress"

# Fechar com motivo (completed | not planned | duplicate)
gh issue close <numero> -R owner/repo --reason completed
```

Ao contrário do GitLab, fechar uma issue no GitHub **não** bloqueia editar milestone ou labels
depois — não existe o problema de "reabrir para mexer em data" descrito no provider GitLab.

## Fluxo — Issues de Spec (pai + sub-issues nativas)

Padrão genérico no `SKILL.md` ("Issues de Spec"). Sub-issues são nativas do GitHub (REST) e a API
pede o **id** interno da issue filha (campo `id`), **não** o número:

```bash
R=owner/repo
# labels (idempotente)
gh label create spec --color 5319E7 --description "Issue-pai de uma spec" --force -R $R
gh label create "spec:016" --color C5B3F2 --description "Spec 016" --force -R $R
gh label create speckit --color 0E8A16 --description "Gerar plan/tasks via Spec Kit" --force -R $R

# criar e capturar número + id
URL=$(gh issue create -R $R --title "..." --body-file .tmp/pai.md --label "spec,spec:016" --assignee "@me")
PAI=${URL##*/}
URL=$(gh issue create -R $R --title "..." --body-file .tmp/filha.md --label "enhancement,spec:016,module:iam" --assignee "@me")
FILHA=${URL##*/}
FILHA_ID=$(gh api repos/$R/issues/$FILHA --jq .id)

# vincular filha ao pai
gh api repos/$R/issues/$PAI/sub_issues -X POST -F sub_issue_id=$FILHA_ID

# listar / conferir progresso
gh api repos/$R/issues/$PAI/sub_issues --jq '.[] | "#\(.number) \(.state) \(.title)"'
gh api repos/$R/issues/$PAI --jq .sub_issues_summary
```

Dependência entre filhas: texto `Depende de #N` na seção `## Dependências` (opcional: `gh api
repos/$R/issues/N/dependencies/blocked_by -X POST -F issue_id=<id>`).

Fechar: filha com `gh issue close <n> --reason completed` depois de conferir o `[x]` no
`tasks.md` do commit; pai só quando `sub_issues_summary` mostrar todas concluídas.

## Fluxo — Milestones

GitHub só tem `due_on` (data de entrega) nativamente — **não existe campo de `start_date`** para
milestone nem para issue via REST/`gh` (só é possível simular com um campo customizado em
GitHub Projects v2, que é outra API). Não presumir paridade com o GitLab nesse ponto.

```bash
# Criar milestone
gh api repos/{owner}/{repo}/milestones -X POST \
  -f title="Agosto/2026" \
  -f description="Milestone referente a Agosto de 2026" \
  -f due_on="2026-08-31T23:59:59Z"

# Listar milestones existentes
gh api repos/{owner}/{repo}/milestones

# Atribuir milestone a uma issue já criada
gh issue edit <numero> -R owner/repo --milestone "Agosto/2026"

# Remover milestone de uma issue
gh issue edit <numero> -R owner/repo --remove-milestone
```

## Fluxo — Buscar Issues por Usuário

```bash
# Num repositório específico
gh issue list -R owner/repo --assignee usuario --state all

# Em todos os repositórios de um usuário/organização, com filtro de data
gh search issues --owner org-ou-usuario --assignee usuario \
  --created ">=2026-07-01" --created "<=2026-07-31" --state all
```

`gh search issues` cobre o caso que no GitLab exige varrer `groups/.../issues` manualmente —
não precisa listar repositórios um a um antes.

## Fluxo — Descobrir se uma Issue já foi Atribuída a Alguém no Passado

Diferente do GitLab (onde o histórico de assignee só existe como nota de sistema, sem endpoint
dedicado), o GitHub expõe isso diretamente na **timeline** da issue:

```bash
gh api repos/{owner}/{repo}/issues/{numero}/timeline --paginate \
  | python3 -c "
import json, sys
events = json.load(sys.stdin)
for e in events:
    if e.get('event') in ('assigned', 'unassigned'):
        print(e['event'], '->', e.get('assignee', {}).get('login'), e.get('created_at'))
"
```

Não precisa paralelizar com `xargs -P` para um volume pequeno de issues — só considerar
paralelizar (mesmo padrão do provider GitLab) se o número de issues a consultar for grande
(dezenas ou mais).

## Labels e Atribuição

Sem separação de escopo por grupo: todas as labels ficam no mesmo repositório. Convenção
recomendada (usada em `SamuelGFDias/condominio_app`, ver histórico de labels criadas em
29/08/2026):

- Labels de **domínio/tipo** (ex: `debito-tecnico`) — categoria transversal do item.
- Labels de **módulo/escopo** (ex: `modulo:iam`, `modulo:financial`) — prefixo `modulo:` +
  nome do módulo/área do sistema.
- Labels de **status** (ex: `in-progress`), se o fluxo de trabalho do repositório usar.

```bash
gh label list -R owner/repo
```

## Observações

- `-R owner/repo` é aceito por praticamente todo subcomando de `gh issue`/`gh label` — não
  precisa exportar variável de ambiente equivalente ao `GITLAB_HOST` do provider GitLab, mas
  fora de um diretório com remote GitHub configurado é obrigatório passar `-R` explicitamente.
- Não existe GraphQL obrigatório para nada documentado aqui — todo fluxo roda via REST
  (`gh api`) ou comandos de alto nível (`gh issue`/`gh label`). GraphQL só entra em cena para
  GitHub Projects v2 (campos customizados), fora do escopo deste provider.
- Issues e Pull Requests compartilham o mesmo namespace de número no GitHub (diferente do
  GitLab, onde issues e work items compartilham IID) — `gh issue view <numero>` falha se o
  número for de um PR, usar `gh pr view <numero>` nesse caso.
