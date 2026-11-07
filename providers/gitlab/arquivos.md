# Provider: GitLab (ses-rj/desenvolvimento)

Referência dos detalhes específicos do GitLab SES-RJ usados pelas skills `issue-factory` e `commiter`.
Este arquivo é **referência** — não é uma skill carregável. As skills apontam para cá para os comandos
concretos.

## Autenticação e host

- Host: `gitlab-prod.saude.rj.gov.br`
- Grupo: `ses-rj/desenvolvimento` (group_id=6)
- Verificar: `glab auth status -h gitlab-prod.saude.rj.gov.br`
- `glab issue update`/`glab issue list` não têm `--hostname`. Fora de um repo git (sem remote),
  definir `export GITLAB_HOST=gitlab-prod.saude.rj.gov.br` antes do comando; `glab api` aceita
  `--hostname` normalmente.
- Dependências (`jq`/`glab`): skill `ses-gitlab-deps`.

## Projetos comuns

- `ses-rj/desenvolvimento/biae/biae`
- `ses-rj/desenvolvimento/amaq/amaq`
- `ses-rj/desenvolvimento/agendamedicamentos/agendamedicamentos`
- `ses-rj/desenvolvimento/talonario/talonario`
- `ses-rj/desenvolvimento/pericia-medica/pericia-medica`
- `ses-rj/desenvolvimento/crachamaster/crachamaster`
- `ses-rj/desenvolvimento/template-dev-ses`
- `ses-rj/desenvolvimento/legados/scp/scp`
- `ses-rj/desenvolvimento/legados/protocolo-online/protocoloonline`
- `ses-rj/desenvolvimento/pesquisasatisfacao/pesquisasatisfacao`

Usar `-R <caminho-completo-do-projeto>` em comandos `glab`.

## Labels por grupo

| Grupo GitLab | Labels |
|-------------|--------|
| `/groups/ses-rj/` | `Backlog`, `In progress`, `Offside`, `Pause` |
| `/groups/ses-rj/desenvolvimento/` | Demais labels por projeto (ex: `Biae`, `Amaq`, `Talonario`, `PericiaMedica`) |

Ao criar issue, sempre incluir: label do projeto (grupo desenvolvimento) + label de status (grupo ses-rj).

## Milestones

- Pertencem ao grupo `/groups/ses-rj/desenvolvimento/` (acessíveis por todos os subprojetos).
- Atribuir: `glab issue update <iid> -R <projeto> --milestone "NomeDoMilestone"`
- Criar milestone de projeto:
  ```bash
  glab api -X POST "projects/ses-rj%2Fdesenvolvimento%2Fbiae%2Fbiae/milestones" \
    --raw-field title="Agosto/2026" \
    --raw-field description="..." \
    --raw-field start_date="2026-08-01" \
    --raw-field due_date="2026-08-31"
  ```

## Usuários (assignee)

| Usuário | GitLab |
|---------|--------|
| Wallace Fortuna | `wallace.fortuna` |
| Flavio Filho | `flavio.filho` |
| Samuel Dias | `samuel.dias` |
| Jonatas Rodrigues | `jonatas.rodrigues` |
| Lucas Jesus | `lucas.jesus` |
| Victor Pinto | `victor.pinto` |

## Criar issue (com arquivo temporário)

Como `glab issue create -d` pode truncar descrições longas ou corromper acentos, salvar em arquivo UTF-8:

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

Após criar, atribuir milestone se informado (ver acima).

## Comentar solução e fechar

```bash
# Comentário com solução (antes de fechar)
glab issue note <iid> -R ses-rj/desenvolvimento/biae/biae \
  -m "## Solução implementada\n\n**Commit:** <hash>\n\nDescrição técnica.\n\n**Arquivos alterados:**\n- \`caminho\`"

# Fechar (via glab)
glab issue update <iid> -R <projeto> --unlabel "In progress"
glab issue close <iid> -R <projeto>
```

## Datas (start_date / due_date)

- `due_date` via REST: `glab issue update <iid> -R <projeto> --due-date 2026-07-14`
- `start_date` **não existe** na REST do GitLab 18.x (só a partir do 19.1) nem no `glab`
  (até v1.111.0 só tem `--due-date`). **Único método: GraphQL `workItemUpdate`**.

### Obter ID global do work item

```bash
glab api "projects/ses-rj%2Fdesenvolvimento%2Fbiae%2Fbiae/issues/<iid>" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])"
```

### Definir datas (issue aberta)

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

### Issue fechada: reabrir → definir datas → fechar

Issues fechadas bloqueiam alteração de datas via REST/`glab`. Usar GraphQL:
`stateEvent: REOPEN` + `startAndDueDateWidget` numa mutação, depois `stateEvent: CLOSE`.

### Validar

```bash
glab api graphql -f query='
query {
  workItem(id: "gid://gitlab/WorkItem/<ID_GLOBAL>") {
    widgets { ... on WorkItemWidgetStartAndDueDate { startDate dueDate } }
  }
}
'
```

Issues e work items compartilham o mesmo namespace de IID — `glab issue update` funciona para ambos.

## Buscar issues por usuário / em massa

```bash
# Listar projetos do grupo
glab api "groups/ses-rj%2Fdesenvolvimento/projects?per_page=100&include_subgroups=true"

# Issues de um usuário em um mês
glab api "groups/ses-rj%2Fdesenvolvimento/issues?per_page=100&state=all&assignee_username=samuel.dias&created_after=2026-07-01&created_before=2026-07-31"
```

## Histórico de assignee (quem já foi atribuído no passado)

`glab issue list`/`.../issues` só retorna o **estado atual** — não há histórico no payload. A Search
API (`scope=notes`) não indexa notas de sistema. **Única fonte: nota de sistema por issue**
(`/projects/:id/issues/:iid/notes`, conteúdo `assigned to @user`/`unassigned @user`). 1 chamada por
issue — rodar em sequência é lento (74 issues ≈ 7min); paralelizar com `xargs -P 15` reduz a ~3s:

```bash
# 1) Listar issues abertas → project_id + iid + ref
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
try: notes = json.load(sys.stdin)
except Exception: sys.exit(0)
for n in notes:
    if n.get('system') and 'samuel.dias' in n.get('body','') and 'assign' in n.get('body','').lower():
        print(n['body'])
")
[ -n "$hit" ] && echo "$ref :: $hit"
EOF
chmod +x /tmp/check_issue.sh

# 3) Rodar em paralelo
cat /tmp/issue_ids.txt | xargs -P 15 -L 1 /tmp/check_issue.sh
```

Troque `samuel.dias` pelo username desejado. A última entrada é o estado mais recente.

## Atribuir milestone em massa para múltiplos usuários

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
