---
name: abrir-issue-gitlab
description: Cria, gerencia e fecha issues no GitLab em projetos do grupo ses-rj/desenvolvimento, com labels, atribuição, milestones e datas.
---

# Skill: abrir-issue-gitlab (Biae)

## Quando executar

Quando houver demandas de desenvolvimento descritas pelo usuario que precisem ser abertas, atualizadas ou fechadas como issues no GitLab.

**Não há atas de reunião ou arquivos `.md` pré-criados**. As demandas são descritas diretamente pelo usuário na conversa.

## Pré-requisitos

- `glab` CLI instalado e autenticado no `gitlab-prod.saude.rj.gov.br`
- Grupo: `ses-rj/desenvolvimento` (group_id=6)
- Projetos dentro deste grupo (ex: `ses-rj/desenvolvimento/biae/biae`, `ses-rj/desenvolvimento/amaq/amaq`, etc.)
- Usuários existentes no GitLab

## Coleta de informações interativas

Antes de criar a issue, **pergunte ao usuário** cada um dos itens abaixo, **a menos que já tenham sido informados via prompt**:

| Item | Perguntar? | Onde pertence | Padrão |
|------|-----------|---------------|--------|
| **Usuário** (assignee) | Sempre, salvo se já passado | — | — |
| **Milestone** | Sempre, salvo se já passado | Grupo `/groups/ses-rj/desenvolvimento/` | — |
| **Projeto** | Sempre, salvo se já passado | — | `ses-rj/desenvolvimento/biae/biae` |
| **Label de status** (Backlog, In progress, Offside, Pause) | Sempre, salvo se já passado | Grupo `/groups/ses-rj/` | — |
| **Label do projeto** (ex: Biae, Amaq) | Sempre, salvo se já passado | Grupo `/groups/ses-rj/desenvolvimento/` | — |

### Regras de labels por grupo

| Grupo GitLab | Labels |
|-------------|--------|
| `/groups/ses-rj/` | `Backlog`, `In progress`, `Offside`, `Pause` |
| `/groups/ses-rj/desenvolvimento/` | Demais labels (ex: `Biae`, `Amaq`, `Talonario`, etc.) |

### Regras de milestones

- **Milestones** pertencem ao grupo `/groups/ses-rj/desenvolvimento/`
- Milestones de grupo são acessíveis por todos os subprojetos

## Fluxo — Criar Issue

### 1. Verificar autenticação

```bash
glab auth status
```

### 2. Coletar as demandas

Cada demanda deve conter:
- **Título** — descrição curta e objetiva
- **US (História de Usuário)** — quem, o que e por quê
- **Solução** — descrição técnica, arquivos alterados, commits relacionados

### 3. Montar labels

Combinar **label de status** + **label do projeto** no formato separado por vírgula:

```
-l "<label-projeto>,<label-status>"
```

Exemplo:
```
-l "Biae,Backlog"
```

### 4. Para cada demanda, preparar arquivo temporário de descrição

Como o `glab issue create -d` pode truncar descrições longas ou corromper acentos, salve o conteúdo em um arquivo temporário UTF-8:

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
```

Após criar, se um milestone foi informado, atribuí-lo:

```bash
glab issue update <iid> -R ses-rj/desenvolvimento/biae/biae --milestone "NomeDoMilestone"
```

> **Nota:** O parâmetro `-R` aceita qualquer projeto em `ses-rj/desenvolvimento`. Ex: `ses-rj/desenvolvimento/amaq/amaq`, `ses-rj/desenvolvimento/talonario/talonario`.

### 5. Limpeza

```bash
rm -f .kilo/tmp/issue_desc.md
```

---

## Fluxo — Adicionar Comentário com Solução

Antes de fechar uma issue, registre a solução como comentário:

```bash
glab issue note <iid> \
  -R ses-rj/desenvolvimento/biae/biae \
  -m "## Solução implementada

**Commit:** <hash>

Descrição técnica do que foi feito.

**Arquivos alterados:**
- \`caminho/do/arquivo\`"
```

---

## Fluxo — Fechar Issue

### Via glab (simples)

```bash
# Remover label de status
glab issue update <iid> -R ses-rj/desenvolvimento/biae/biae --unlabel "In progress"

# Fechar a issue
glab issue close <iid> -R ses-rj/desenvolvimento/biae/biae
```

### Via GraphQL (quando precisar manipular datas junto)

Após fechar uma issue, campos como `due_date` e `start_date` **não podem ser alterados** via REST ou `glab issue update`. Use a mutação GraphQL com `stateEvent: REOPEN` antes de definir datas, depois `stateEvent: CLOSE` para fechar novamente (ver [Fluxo — Definir Datas](#fluxo--definir-datas-start_date--due_date), Passo 3).

---

## Fluxo — Atribuir Milestone

### Milestone de grupo (compartilhado entre projetos)

Milestones pertencem ao grupo `/groups/ses-rj/desenvolvimento/`.

```bash
# Atribuir uma issue a um milestone
glab issue update <iid> -R ses-rj/desenvolvimento/biae/biae --milestone "Julho/2026"

# Atribuir várias issues no mesmo projeto
for iid in 1 2 3 4 5; do
  glab issue update "$iid" -R ses-rj/desenvolvimento/amaq/amaq --milestone "Julho/2026"
done
```

### Criar milestone no projeto (se não existir)

```bash
glab api -X POST "projects/ses-rj%2Fdesenvolvimento%2Fbiae%2Fbiae/milestones" \
  --raw-field title="Agosto/2026" \
  --raw-field description="Milestone referente ao mês de Agosto de 2026" \
  --raw-field start_date="2026-08-01" \
  --raw-field due_date="2026-08-31"
```

---

## Fluxo — Definir Datas (start_date / due_date)

### Para `due_date` apenas (issue nova ou aberta)

`glab issue update` suporta `--due-date` diretamente:

```bash
glab issue update <iid> -R ses-rj/desenvolvimento/biae/biae --due-date 2026-07-14
```

### Para `start_date` — GraphQL (único método)

> **IMPORTANTE:** Nem o `glab` CLI (até v1.111.0) nem a REST API suportam `start_date` no GitLab 18.x.  
> O `glab issue update` só tem `--due-date`, sem `--start-date`.  
> A REST API só aceita `start_date` a partir do **GitLab 19.1**.  
> **Único método funcional em 18.x: GraphQL API** via `workItemUpdate`.

#### Passo 1 — Obter o ID global do work item

```bash
glab api "projects/ses-rj%2Fdesenvolvimento%2Fbiae%2Fbiae/issues/<iid>" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])"
```

O ID retornado (ex: `849`) deve ser usado como `gid://gitlab/WorkItem/<id>`.

#### Passo 2 — Definir datas via mutação GraphQL

```bash
# Issue aberta: apenas definir datas
glab api graphql -f query='
mutation {
  workItemUpdate(input: {
    id: "gid://gitlab/WorkItem/<ID_GLOBAL>",
    startAndDueDateWidget: {
      startDate: "2026-07-14",
      dueDate: "2026-07-14"
    }
  }) {
    errors
  }
}
'
```

#### Passo 3 — Issue fechada: reabrir, definir datas e fechar

```bash
# Reabrir + definir datas (em uma única mutação)
glab api graphql -f query='
mutation {
  workItemUpdate(input: {
    id: "gid://gitlab/WorkItem/<ID_GLOBAL>",
    stateEvent: REOPEN,
    startAndDueDateWidget: {
      startDate: "2026-07-14",
      dueDate: "2026-07-14"
    }
  }) {
    errors
  }
}
'

# Depois fechar
glab api graphql -f query='
mutation {
  workItemUpdate(input: {
    id: "gid://gitlab/WorkItem/<ID_GLOBAL>",
    stateEvent: CLOSE
  }) {
    errors
  }
}
'
```

#### Definir datas em lote (múltiplas issues, inclusive fechadas)

```bash
# 1) Obter IDs globais de uma vez
for iid in 40 41 42; do
  id=$(glab api "projects/ses-rj%2Fdesenvolvimento%2Fbiae%2Fbiae/issues/$iid" \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
  echo "$iid $id"
done

# 2) Para cada issue, reabrir + definir datas (em paralelo se possível)
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
    workItemUpdate(input: {
      id: "gid://gitlab/WorkItem/'"$id"'",
      stateEvent: CLOSE
    }) { errors }
  }
  '
done
```

#### Validar datas definidas

```bash
glab api graphql -f query='
query {
  workItem(id: "gid://gitlab/WorkItem/<ID_GLOBAL>") {
    id
    widgets {
      ... on WorkItemWidgetStartAndDueDate {
        startDate
        dueDate
      }
    }
  }
}
'
```

---

## Fluxo — Buscar Issues por Usuário em Todos os Projetos do Grupo

```bash
# Listar todos os projetos
glab api "groups/ses-rj%2Fdesenvolvimento/projects?per_page=100&include_subgroups=true"

# Buscar issues de um usuário específico em Julho/2026
glab api "groups/ses-rj%2Fdesenvolvimento/issues?per_page=100&state=all&assignee_username=samuel.dias&created_after=2026-07-01&created_before=2026-07-31"
```

---

## Fluxo — Descobrir se uma Issue já foi Atribuída a Alguém no Passado

**Importante:** `glab issue list`/`glab api .../issues` só retorna o **estado atual** (`assignee`/`assignees`). Não existe campo de histórico nesse payload — não adianta filtrar isso com `jq`, o dado não está lá. A Search API (`scope=notes`) também não ajuda: notas de sistema (as que registram troca de assignee) não são indexadas pela busca, mesmo em projeto único (`scope=notes` retorna `[]` mesmo quando a nota existe).

A única fonte de verdade é a nota de sistema por issue (`assigned to @user` / `unassigned @user`), disponível em `/projects/:id/issues/:iid/notes`. Isso exige 1 chamada por issue — **mas rodar essas chamadas em sequência é o que fica lento** (74 issues × ~6s = 7+min). Paralelizar com `xargs -P` resolve (as mesmas 74 issues em ~3s):

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

Troque `samuel.dias` pelo username desejado. O resultado mostra `assigned to @user` / `unassigned @user` na ordem cronológica das notas — a última entrada é o estado mais recente daquela troca.

**Nota sobre `--hostname`:** `glab issue update`/`glab issue list` não têm flag `--hostname`. Fora de um repositório git local (sem remote configurado), definir `export GITLAB_HOST=gitlab-prod.saude.rj.gov.br` antes do comando resolve; `glab api` aceita `--hostname` normalmente.

---

## Fluxo — Atribuir Milestone em Massa para Múltiplos Usuários

```bash
for user in flavio.filho samuel.dias jonatas.rodrigues lucas.jesus victor.pinto; do
  glab api "groups/ses-rj%2Fdesenvolvimento/issues?per_page=100&state=all&assignee_username=$user&created_after=2026-07-01&created_before=2026-07-31" \
    | node -e "
const fs = require('fs');
const data = JSON.parse(fs.readFileSync(0, 'utf8'));
data.forEach(i => console.log(i.project_id + '|' + i.iid));
" | while IFS='|' read -r pid iid; do
    # Mapear project_id para path (consultar via API)
    path=$(glab api "projects/$pid" 2>/dev/null | node -e "const fs=require('fs');console.log(JSON.parse(fs.readFileSync(0,'utf8')).path_with_namespace)")
    glab issue update "$iid" -R "$path" --milestone "Julho/2026"
  done
done
```

---

## Labels

### Escopo de labels por grupo

| Grupo GitLab | Labels |
|-------------|--------|
| `/groups/ses-rj/` | `Backlog`, `In progress`, `Offside`, `Pause` |
| `/groups/ses-rj/desenvolvimento/` | Demais labels por projeto (ex: `Biae`, `Amaq`, `Talonario`, `PericiaMedica`) |

Ao criar a issue, sempre incluir:
1. **Label do projeto** (ex: `Biae`) — grupo `/groups/ses-rj/desenvolvimento/`
2. **Label de status** (ex: `Backlog`) — grupo `/groups/ses-rj/`

## Atribuição por usuário

| Usuário | GitLab |
|---------|--------|
| Wallace Fortuna | `wallace.fortuna` |
| Flavio Filho | `flavio.filho` |
| Samuel Dias | `samuel.dias` |
| Jonatas Rodrigues | `jonatas.rodrigues` |
| Lucas Jesus | `lucas.jesus` |
| Victor Pinto | `victor.pinto` |

## Estrutura esperada de cada issue

1. **Título** — descrição objetiva (ver padrão abaixo)
2. **US (História de Usuário)** — "Como [papel], quero [funcionalidade], para [benefício]"
3. **Descrição da solução** — implementação, arquivos alterados, commits relacionados

## Padrão de título de issue

O título da issue **não é** mensagem de commit. Formato:

```
<Módulo/Escopo> - <Ação no infinitivo> <complemento>
```

- **`<Módulo/Escopo>`**: a tela, entidade, componente ou área do sistema afetada (ex: `Recepção`, `Tabela Recepção`, `Editar dados pessoais`, `Migrations`, `Testes`, `Build`, `Agenda`). Deve ser o que a pessoa reconhece de imediato ao escanear a lista de issues — é o que aparece primeiro, antes do hífen.
- **Separador**: ` - ` (espaço-hífen-espaço) entre módulo e ação.
- **`<Ação>`**: frase objetiva em português, iniciando com verbo no infinitivo que descreva a ação/resultado esperado (ex: `Corrigir`, `Adicionar`, `Padronizar`, `Validar`, `Permitir`, `Remover`, `Investigar`, `Ajustar`, `Configurar`, `Incluir`).
- Primeira letra maiúscula em cada parte (módulo e ação), resto em minúsculas — exceto nomes próprios, siglas e identificadores de código (classes, métodos, tabelas).
- **Proibido** prefixo de conventional commits no título: `feat:`, `fix:`, `bugfix:`, `refactor:`, `build:`, `test:`, `style:`, `perf:`, `docs:`, `chore:`. Esses rótulos pertencem à mensagem de commit/PR, não ao título da issue — usar labels do projeto para categorizar, não o texto do título.
- Sem emojis no título.
- Sem sufixos técnicos entre parênteses (ex: `(no-op)`) — esse detalhe vai na descrição/US, não no título.
- O título deve ser autoexplicativo por si só, sem precisar abrir a issue para entender do que se trata.

Exceção tolerada: prefixo entre colchetes com código de requisito (ex: `[RF-14]`, `[Melhoria]`, `[Correção]`) pode conviver **antes** do módulo, quando já for a convenção adotada no projeto — mas nunca substituir o formato `Módulo - Ação`, e nunca misturar com prefixo de conventional commit.

**Exemplos (antes → depois):**
- `refactor: adicionar IDesignTimeDbContextFactory para gerar migrations sem as ~34 variáveis de ambiente` → `Migrations - Adicionar IDesignTimeDbContextFactory para gerar sem exigir variáveis de ambiente de runtime`
- `test: RollForward ausente em Talonario.Api.Tests e Infra.CrossCutting.Tests impede rodar a suíte local` → `Testes - Configurar RollForward em Talonario.Api.Tests e Infra.CrossCutting.Tests para rodar a suíte localmente`
- `build: build da solução dispara o npm build e apaga o wwwroot da Api` → `Build - Corrigir build da solução para não disparar o build do Angular e apagar o wwwroot da Api`
- `refactor: validação de duplicidade de período em ExisteAgendaData nunca dispara (no-op)` → `Agenda - Corrigir validação de duplicidade de período em ExisteAgendaData que nunca dispara`

Referência de bom uso já existente no grupo: `Recepção - Adicionar modal assim que entrar na recepção`, `Tabela Recepção - Adicionar coluna de justificativa`, `Editar dados pessoais - Incluir o alerta de cautela no editar também` (`pericia-medica#113-115`).

Ao criar uma issue nova (fluxo "Criar Issue" acima) ou ao revisar issues existentes num projeto, sempre validar o título contra este padrão antes de submeter.

## Observações

- Projetos comuns: `biae/biae`, `amaq/amaq`, `agendamedicamentos/agendamedicamentos`, `talonario/talonario`, `pericia-medica/pericia-medica`, `crachamaster/crachamaster`, `template-dev-ses`, `legados/scp/scp`, `legados/protocolo-online/protocoloonline`, `pesquisasatisfacao/pesquisasatisfacao`
- Usar `-R` com o caminho completo do projeto
- Para descrições longas ou com acentos, sempre usar arquivo temporário com `-d "$(cat ...)"`
- Issues e **work items** compartilham o mesmo namespace de IID — `glab issue update` funciona para ambos
- Milestones de grupo (`ses-rj/desenvolvimento`) são acessíveis por todos os subprojetos; milestones de projeto são específicos
- O group_id do `ses-rj/desenvolvimento` é `6` (usado em endpoints de grupo)
- As labels `Backlog`, `In progress`, `Offside`, `Pause` estão no grupo `/groups/ses-rj/`. As demais labels (ex: `Biae`) estão em `/groups/ses-rj/desenvolvimento/`
- **GraphQL vs REST:** A REST API do GitLab 18.x **não** suporta `start_date` em issues (campo introduzido apenas no GitLab 19.1). Usar sempre a mutação GraphQL `workItemUpdate` com `startAndDueDateWidget` para definir `start_date` e `due_date` simultaneamente
- **Issue fechada:** Issues fechadas bloqueiam alteração de datas via REST/`glab`. Usar GraphQL com `stateEvent: REOPEN` → definir datas → `stateEvent: CLOSE`
